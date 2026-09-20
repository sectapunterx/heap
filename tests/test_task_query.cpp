// TaskQuery: the half of the query language that decides whether a given task
// satisfies a clause. QueryParser has been in the tree, finished and tested,
// with no production caller — it turns text into clauses and stops there.
//
// Pure and headless: no AppController, no models, no QApplication.

#include "Models.h"

#include "query/TaskQuery.h"

#include <QDate>
#include <QDateTime>

#include <gtest/gtest.h>

using heap::query::TaskQuery;

namespace {

const QDate kToday(2026, 9, 20);  // a Sunday, so "friday" is unambiguous

Task mk(const QString& id, const QString& status = QStringLiteral("todo"), const QString& priority = QStringLiteral("P2")) {
  Task t;
  t.id = id;
  t.title = QStringLiteral("title of ") + id;
  t.status = status;
  t.priority = priority;
  return t;
}

TaskQuery q(const QString& text) {
  return TaskQuery::compile(text, kToday);
}

}  // namespace

// ─── What counts as a query at all ───

TEST(TaskQuery, PlainTextIsNotAQueryAndIsAllFreeText) {
  const TaskQuery query = q(QStringLiteral("fix the handover"));
  EXPECT_FALSE(query.isQuery());
  EXPECT_EQ(query.freeText(), QStringLiteral("fix the handover"));
  // With no clauses, everything matches — the caller does its own substring.
  EXPECT_TRUE(query.matches(mk(QStringLiteral("A"))));
}

TEST(TaskQuery, AnUnknownFieldIsJustASearchWord) {
  // "http://x" and "note:foo" both contain a colon; only known fields count.
  const TaskQuery query = q(QStringLiteral("note:foo https://x/y"));
  EXPECT_FALSE(query.isQuery());
  EXPECT_EQ(query.freeText(), QStringLiteral("note:foo https://x/y"));
}

TEST(TaskQuery, ClausesAndFreeTextCompose) {
  const TaskQuery query = q(QStringLiteral("status:blocked login"));
  EXPECT_TRUE(query.isQuery());
  // The clause is consumed; only the loose word is searched for.
  EXPECT_EQ(query.freeText(), QStringLiteral("login"));
  EXPECT_TRUE(query.matches(mk(QStringLiteral("A"), QStringLiteral("blocked"))));
  EXPECT_FALSE(query.matches(mk(QStringLiteral("B"), QStringLiteral("todo"))));
}

// ─── Clause semantics ───

TEST(TaskQuery, StatusAndPriorityMatchCaseInsensitivelyAndAsSets) {
  EXPECT_TRUE(q(QStringLiteral("status:BLOCKED")).matches(mk(QStringLiteral("A"), QStringLiteral("blocked"))));

  const TaskQuery two = q(QStringLiteral("priority:P0,P1"));
  EXPECT_TRUE(two.matches(mk(QStringLiteral("A"), QStringLiteral("todo"), QStringLiteral("P0"))));
  EXPECT_TRUE(two.matches(mk(QStringLiteral("B"), QStringLiteral("todo"), QStringLiteral("P1"))));
  EXPECT_FALSE(two.matches(mk(QStringLiteral("C"), QStringLiteral("todo"), QStringLiteral("P2"))));
}

TEST(TaskQuery, SeveralClausesAreAnded) {
  const TaskQuery query = q(QStringLiteral("status:prog priority:P0"));
  EXPECT_TRUE(query.matches(mk(QStringLiteral("A"), QStringLiteral("prog"), QStringLiteral("P0"))));
  EXPECT_FALSE(query.matches(mk(QStringLiteral("B"), QStringLiteral("prog"), QStringLiteral("P2"))));
  EXPECT_FALSE(query.matches(mk(QStringLiteral("C"), QStringLiteral("todo"), QStringLiteral("P0"))));
}

TEST(TaskQuery, TagMatchesAnyLabel) {
  Task t = mk(QStringLiteral("A"));
  t.labels = {Label{QStringLiteral("Infra"), QString()}, Label{QStringLiteral("bug"), QString()}};

  EXPECT_TRUE(q(QStringLiteral("tag:infra")).matches(t));   // case-insensitive
  EXPECT_TRUE(q(QStringLiteral("tag:ci,bug")).matches(t));  // any of the set
  EXPECT_FALSE(q(QStringLiteral("tag:windows")).matches(t));
  EXPECT_FALSE(q(QStringLiteral("tag:infra")).matches(mk(QStringLiteral("B"))));
}

TEST(TaskQuery, MentionMatchesTheAssigneeOrAnAtNameInTheText) {
  Task assigned = mk(QStringLiteral("A"));
  assigned.assignee = QStringLiteral("Ada");
  EXPECT_TRUE(q(QStringLiteral("mention:@ada")).matches(assigned));
  EXPECT_TRUE(q(QStringLiteral("mention:ada")).matches(assigned)) << "the @ is optional";

  Task mentioned = mk(QStringLiteral("B"));
  mentioned.desc = QStringLiteral("ask @grace about the trace");
  EXPECT_TRUE(q(QStringLiteral("mention:@grace")).matches(mentioned));

  EXPECT_FALSE(q(QStringLiteral("mention:@ada")).matches(mk(QStringLiteral("C"))));
  // A bare name in the text is not a mention.
  Task bare = mk(QStringLiteral("D"));
  bare.desc = QStringLiteral("ada wrote this");
  EXPECT_FALSE(q(QStringLiteral("mention:@ada")).matches(bare));
}

// ─── Dates ───

TEST(TaskQuery, DeadlineComparesAgainstAResolvedDate) {
  Task soon = mk(QStringLiteral("A"));
  soon.dueAt = QDateTime(kToday.addDays(2), QTime(0, 0));
  Task later = mk(QStringLiteral("B"));
  later.dueAt = QDateTime(kToday.addDays(30), QTime(0, 0));

  EXPECT_TRUE(q(QStringLiteral("deadline:<7d")).matches(soon));
  EXPECT_FALSE(q(QStringLiteral("deadline:<7d")).matches(later));
  EXPECT_TRUE(q(QStringLiteral("deadline:>7d")).matches(later));
  // Week and month shorthands.
  EXPECT_TRUE(q(QStringLiteral("deadline:<1w")).matches(soon));
  EXPECT_TRUE(q(QStringLiteral("deadline:<2m")).matches(later));
}

TEST(TaskQuery, DeadlineAcceptsWhatTheRestOfTheAppAccepts) {
  Task t = mk(QStringLiteral("A"));
  t.dueAt = QDateTime(QDate(2026, 9, 24), QTime(0, 0));
  // An ISO date, and the natural-language forms the task editor takes.
  EXPECT_TRUE(q(QStringLiteral("deadline:2026-09-24")).matches(t));
  EXPECT_TRUE(q(QStringLiteral("deadline:<2026-09-30")).matches(t));
  EXPECT_FALSE(q(QStringLiteral("deadline:<2026-09-01")).matches(t));
}

TEST(TaskQuery, AnUndatedTaskSatisfiesNoComparisonButMatchesNone) {
  const Task undated = mk(QStringLiteral("A"));
  // Not "before Friday" — simply not scheduled.
  EXPECT_FALSE(q(QStringLiteral("deadline:<7d")).matches(undated));
  EXPECT_FALSE(q(QStringLiteral("deadline:>7d")).matches(undated));
  EXPECT_TRUE(q(QStringLiteral("deadline:none")).matches(undated));

  Task dated = mk(QStringLiteral("B"));
  dated.dueAt = QDateTime(kToday, QTime(0, 0));
  EXPECT_FALSE(q(QStringLiteral("deadline:none")).matches(dated));
}

TEST(TaskQuery, AnUnreadableDateDropsTheClauseRatherThanMatchingNothing) {
  // "deadline:banana" is a typo, not an instruction to show an empty board.
  const TaskQuery query = q(QStringLiteral("deadline:banana status:todo"));
  EXPECT_TRUE(query.isQuery());
  EXPECT_TRUE(query.matches(mk(QStringLiteral("A"), QStringLiteral("todo"))));
  EXPECT_FALSE(query.matches(mk(QStringLiteral("B"), QStringLiteral("done"))));
}

// ─── Clauses that parse but do not filter here ───

TEST(TaskQuery, SortAndLimitAreRecognisedWithoutFiltering) {
  // They belong to a saved view, not to a board filter — but they must not be
  // substring-matched either, or "sort:deadline" would find nothing.
  const TaskQuery query = q(QStringLiteral("sort:-deadline limit:20"));
  EXPECT_TRUE(query.isQuery());
  EXPECT_TRUE(query.freeText().isEmpty());
  EXPECT_TRUE(query.matches(mk(QStringLiteral("A"))));
}

TEST(TaskQuery, ProfileParsesAndIsIgnoredOnASingleProfileView) {
  const TaskQuery query = q(QStringLiteral("profile:other"));
  EXPECT_TRUE(query.isQuery());
  EXPECT_TRUE(query.matches(mk(QStringLiteral("A")))) << "an ignored clause must not filter everything out";
}

TEST(TaskQuery, EmptyInputIsNeitherQueryNorFilter) {
  const TaskQuery query = q(QString());
  EXPECT_FALSE(query.isQuery());
  EXPECT_TRUE(query.freeText().isEmpty());
  EXPECT_TRUE(query.matches(mk(QStringLiteral("A"))));
}

TEST(TaskQuery, TheFieldListIsWhatTheParserAccepts) {
  const QStringList fields = heap::query::queryFields();
  for(const char* f : {"status", "priority", "deadline", "tag", "mention", "profile", "sort", "limit"}) {
    EXPECT_TRUE(fields.contains(QLatin1String(f))) << f << " is missing from the advertised field list";
  }
}
