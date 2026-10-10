// TaskQuery: the half of the query language that decides whether a given task
// satisfies a clause. QueryParser has been in the tree, finished and tested,
// with no production caller — it turns text into clauses and stops there.
//
// Pure and headless: no AppController, no models, no QApplication.

#include "Models.h"

#include "query/TaskQuery.h"

#include <QDate>
#include <QDateTime>
#include <QVariantList>
#include <QVariantMap>

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

// ─── The audit's TASKS-21: the query speaks the board's language ───

namespace {

const QVariantList kColumns = {
    QVariantMap{{"id", "todo"}, {"name", "To Do"}},
    QVariantMap{{"id", "prog"}, {"name", "In Progress"}},
    QVariantMap{{"id", "review"}, {"name", "Code Review"}},
    QVariantMap{{"id", "done"}, {"name", "Done"}},
};

TaskQuery qc(const QString& text) {
  return TaskQuery::compile(text, kToday, kColumns);
}

}  // namespace

TEST(TaskQuery, StatusIsNamedAsTheBoardShowsIt) {
  const Task review = mk(QStringLiteral("A"), QStringLiteral("review"));
  const Task prog = mk(QStringLiteral("B"), QStringLiteral("prog"));
  EXPECT_TRUE(qc(QStringLiteral("status:review")).matches(review));
  EXPECT_TRUE(qc(QStringLiteral("status:\"Code Review\"")).matches(review));
  EXPECT_TRUE(qc(QStringLiteral("status:code-review")).matches(review));
  EXPECT_TRUE(qc(QStringLiteral("status:in-progress")).matches(prog));
  EXPECT_TRUE(qc(QStringLiteral("status:\"in progress\"")).matches(prog));
  EXPECT_FALSE(qc(QStringLiteral("status:in-progress")).matches(review));
}

TEST(TaskQuery, HashIsALabelButANumberIsAnIssue) {
  Task t = mk(QStringLiteral("A"));
  t.labels = {Label{QStringLiteral("infra"), QString()}};
  EXPECT_TRUE(qc(QStringLiteral("#infra")).matches(t));
  EXPECT_FALSE(qc(QStringLiteral("#infra")).matches(mk(QStringLiteral("B"))));
  const TaskQuery issue = qc(QStringLiteral("#42"));
  EXPECT_FALSE(issue.isQuery());
  EXPECT_EQ(issue.freeText(), QStringLiteral("#42"));
}

TEST(TaskQuery, DueTodayOverdueAndWeek) {
  Task today = mk(QStringLiteral("A"));
  today.dueAt = QDateTime(kToday, QTime(0, 0));
  Task late = mk(QStringLiteral("B"));
  late.dueAt = QDateTime(kToday.addDays(-3), QTime(0, 0));
  Task lateDone = late;
  lateDone.status = QStringLiteral("done");
  Task next = mk(QStringLiteral("C"));
  next.dueAt = QDateTime(kToday.addDays(1), QTime(0, 0));  // kToday is a Sunday

  EXPECT_TRUE(qc(QStringLiteral("due:today")).matches(today));
  EXPECT_FALSE(qc(QStringLiteral("due:today")).matches(late));
  EXPECT_TRUE(qc(QStringLiteral("due:overdue")).matches(late));
  EXPECT_FALSE(qc(QStringLiteral("due:overdue")).matches(lateDone)) << "done is not overdue";
  EXPECT_TRUE(qc(QStringLiteral("due:week")).matches(today));
  EXPECT_FALSE(qc(QStringLiteral("due:week")).matches(next)) << "Monday is next week";
  EXPECT_TRUE(qc(QStringLiteral("deadline:overdue")).matches(late)) << "due: and deadline: are one field";
}

TEST(TaskQuery, IsOpenDoneArchived) {
  Task done = mk(QStringLiteral("A"), QStringLiteral("done"));
  Task archived = mk(QStringLiteral("B"));
  archived.archived = true;
  EXPECT_TRUE(qc(QStringLiteral("is:open")).matches(mk(QStringLiteral("C"))));
  EXPECT_FALSE(qc(QStringLiteral("is:open")).matches(done));
  EXPECT_FALSE(qc(QStringLiteral("is:open")).matches(archived));
  EXPECT_TRUE(qc(QStringLiteral("is:done")).matches(done));
  EXPECT_TRUE(qc(QStringLiteral("is:archived")).matches(archived));
}

TEST(TaskQuery, NegationAndOr) {
  const Task p0 = mk(QStringLiteral("A"), QStringLiteral("todo"), QStringLiteral("P0"));
  const Task blocked = mk(QStringLiteral("B"), QStringLiteral("blocked"), QStringLiteral("P3"));
  const Task other = mk(QStringLiteral("C"), QStringLiteral("todo"), QStringLiteral("P3"));
  const TaskQuery either = TaskQuery::compile(QStringLiteral("priority:p0 OR status:blocked"), kToday);
  EXPECT_TRUE(either.matches(p0));
  EXPECT_TRUE(either.matches(blocked));
  EXPECT_FALSE(either.matches(other));

  EXPECT_FALSE(qc(QStringLiteral("-status:done")).matches(mk(QStringLiteral("D"), QStringLiteral("done"))));
  EXPECT_TRUE(qc(QStringLiteral("-status:done")).matches(other));
  // A negated word excludes on the task's text.
  const TaskQuery noTitle = qc(QStringLiteral("-title"));
  EXPECT_TRUE(noTitle.isQuery());
  EXPECT_FALSE(noTitle.matches(other)) << "every mk() title contains 'title'";
}

// TASKS-4 (2026-09-30-1): OR splits search words too. "alpha OR beta" used to
// search for the phrase "alpha beta" and find nothing.
TEST(TaskQuery, OrBetweenWords) {
  Task alpha = mk(QStringLiteral("A"));
  alpha.title = QStringLiteral("qzalpha login");
  Task beta = mk(QStringLiteral("B"), QStringLiteral("done"));
  beta.title = QStringLiteral("qzbeta signup");
  Task other = mk(QStringLiteral("C"), QStringLiteral("done"));

  for(const char* text : {"qzalpha OR qzbeta", "qzalpha | qzbeta"}) {
    const TaskQuery either = qc(QString::fromLatin1(text));
    EXPECT_TRUE(either.isQuery()) << text;
    EXPECT_TRUE(either.freeText().isEmpty()) << "the words must not also be ANDed as one phrase: " << text;
    EXPECT_TRUE(either.matches(alpha)) << text;
    EXPECT_TRUE(either.matches(beta)) << text;
    EXPECT_FALSE(either.matches(other)) << text;
  }
  // A clause on one side, a word on the other.
  const TaskQuery mixed = qc(QStringLiteral("is:open OR qzbeta"));
  EXPECT_TRUE(mixed.matches(alpha)) << "open";
  EXPECT_TRUE(mixed.matches(beta)) << "qzbeta, though done";
  EXPECT_FALSE(mixed.matches(other));
  // Words of one side stay a phrase, as without OR; the caller's haystack wins.
  const TaskQuery phrase = qc(QStringLiteral("qzalpha login OR nothing-here"));
  EXPECT_TRUE(phrase.matches(alpha));
  EXPECT_TRUE(phrase.matches(other, QStringLiteral("cached haystack: qzalpha login")));
  // No OR: unchanged — one free text for the caller.
  EXPECT_EQ(qc(QStringLiteral("status:done qzbeta")).freeText(), QStringLiteral("qzbeta"));
  EXPECT_EQ(qc(QStringLiteral("qzalpha OR")).freeText(), QStringLiteral("qzalpha"));
}

TEST(TaskQuery, NonsenseIsReportedNotSilentlySearched) {
  const TaskQuery query = qc(QStringLiteral("stauts:done status:nope priority:p9 due:banana is:weird login"));
  const QStringList bad = query.unknownClauses();
  for(const char* tok : {"stauts:done", "status:nope", "priority:p9", "due:banana", "is:weird"}) {
    EXPECT_TRUE(bad.contains(QLatin1String(tok))) << tok << " was not reported";
  }
  EXPECT_FALSE(bad.contains(QStringLiteral("login")));
  EXPECT_TRUE(qc(QStringLiteral("status:done #infra")).unknownClauses().isEmpty());
  // A URL is text, not a clause.
  EXPECT_TRUE(qc(QStringLiteral("https://x/y")).unknownClauses().isEmpty());
}

// IDIOT-TASKS-11: a saved view's stored query is strict about columns. A
// typed query drops a status that names no column; a saved one matches
// nothing for it, and still reports it.
TEST(TaskQuery, AStrictQueryMatchesNothingForAGoneColumn) {
  QVariantList cols;
  cols << QVariantMap{{"id", "todo"}, {"name", "To Do"}} << QVariantMap{{"id", "done"}, {"name", "Done"}};
  const Task open = mk(QStringLiteral("A"), QStringLiteral("todo"));
  const TaskQuery typed = TaskQuery::compile(QStringLiteral("status:review"), kToday, cols);
  EXPECT_TRUE(typed.matches(open)) << "a typed typo narrowed to nothing";
  EXPECT_TRUE(typed.unknownClauses().contains(QStringLiteral("status:review")));
  const TaskQuery strict = TaskQuery::compile(QStringLiteral("status:review"), kToday, cols, {}, true);
  EXPECT_FALSE(strict.matches(open)) << "a view on a deleted column showed every task";
  EXPECT_TRUE(strict.unknownClauses().contains(QStringLiteral("status:review")));
  // A column it still names keeps matching; the gone one adds nothing.
  const TaskQuery partly = TaskQuery::compile(QStringLiteral("status:review,todo"), kToday, cols, {}, true);
  EXPECT_TRUE(partly.matches(open));
  EXPECT_FALSE(partly.matches(mk(QStringLiteral("B"), QStringLiteral("done"))));
  // Negated, a gone column excludes nothing.
  EXPECT_TRUE(TaskQuery::compile(QStringLiteral("-status:review"), kToday, cols, {}, true).matches(open));
}

// ─── APP-250: planning clauses ───

TEST(TaskQueryPlanning, ScheduledReadsLikeDue) {
  Task today = mk(QStringLiteral("T"));
  today.scheduledAt = QDateTime(kToday, QTime(10, 0));
  Task later = mk(QStringLiteral("L"));
  later.scheduledAt = QDateTime(kToday.addDays(10), QTime(0, 0));
  const Task none = mk(QStringLiteral("N"));
  EXPECT_TRUE(q(QStringLiteral("scheduled:today")).matches(today));
  EXPECT_FALSE(q(QStringLiteral("scheduled:today")).matches(later));
  EXPECT_TRUE(q(QStringLiteral("scheduled:none")).matches(none));
  EXPECT_FALSE(q(QStringLiteral("scheduled:none")).matches(today));
  EXPECT_TRUE(q(QStringLiteral("scheduled:>3d")).matches(later));
  EXPECT_FALSE(q(QStringLiteral("scheduled:>3d")).matches(none));
  EXPECT_TRUE(q(QStringLiteral("-scheduled:none")).matches(later));
  EXPECT_TRUE(q(QStringLiteral("scheduled:banana")).unknownClauses().contains(QStringLiteral("scheduled:banana")));
}

TEST(TaskQueryPlanning, EstimateComparesMinutesAndNoneIsItsOwnThing) {
  Task small = mk(QStringLiteral("S"));
  small.estimateMinutes = 20;
  Task big = mk(QStringLiteral("B"));
  big.estimateMinutes = 150;
  const Task none = mk(QStringLiteral("N"));
  EXPECT_TRUE(q(QStringLiteral("estimate:<30m")).matches(small));
  EXPECT_FALSE(q(QStringLiteral("estimate:<30m")).matches(none));  // no estimate is not "small"
  EXPECT_TRUE(q(QStringLiteral("estimate:>2h")).matches(big));
  EXPECT_TRUE(q(QStringLiteral("estimate:>1.5ч")).matches(big));
  EXPECT_TRUE(q(QStringLiteral("estimate:20")).matches(small));
  EXPECT_TRUE(q(QStringLiteral("estimate:none")).matches(none));
  EXPECT_FALSE(q(QStringLiteral("estimate:none")).matches(small));
  EXPECT_FALSE(q(QStringLiteral("estimate:lots")).unknownClauses().isEmpty());
}

TEST(TaskQueryPlanning, SomedayUnscheduledAndBranch) {
  Task parked = mk(QStringLiteral("P"));
  parked.someday = true;
  Task open = mk(QStringLiteral("O"));
  open.branch = QStringLiteral("fix/login-rate-limit");
  Task planned = mk(QStringLiteral("D"));
  planned.scheduledAt = QDateTime(kToday, QTime(9, 0));
  const Task done = mk(QStringLiteral("X"), QStringLiteral("done"));
  EXPECT_TRUE(q(QStringLiteral("is:someday")).matches(parked));
  EXPECT_FALSE(q(QStringLiteral("is:someday")).matches(open));
  EXPECT_TRUE(q(QStringLiteral("is:unscheduled")).matches(open));
  EXPECT_FALSE(q(QStringLiteral("is:unscheduled")).matches(parked));
  EXPECT_FALSE(q(QStringLiteral("is:unscheduled")).matches(planned));
  EXPECT_FALSE(q(QStringLiteral("is:unscheduled")).matches(done));
  EXPECT_TRUE(q(QStringLiteral("branch:login")).matches(open));
  EXPECT_FALSE(q(QStringLiteral("branch:login")).matches(parked));
  EXPECT_TRUE(q(QStringLiteral("branch:none")).matches(parked));
  EXPECT_TRUE(q(QStringLiteral("is:someday OR branch:login")).matches(open));
}

TEST(TaskQueryPlanning, BlockedNeedsAnOpenBlocker) {
  Task blocker = mk(QStringLiteral("A"));
  blocker.links = {TaskLink{QStringLiteral("blocks"), QStringLiteral("B")}};
  const Task blocked = mk(QStringLiteral("B"));
  Task doneBlocker = mk(QStringLiteral("C"), QStringLiteral("done"));
  doneBlocker.links = {TaskLink{QStringLiteral("blocks"), QStringLiteral("D")}};
  const Task freed = mk(QStringLiteral("D"));
  const QVector<Task> all{blocker, blocked, doneBlocker, freed};
  TaskQuery query = q(QStringLiteral("is:blocked"));
  ASSERT_TRUE(query.usesBlocked());
  query.setBlockedIds(heap::query::openlyBlockedIds(all, [](const Task& t) {
    return t.status == QStringLiteral("done");
  }));
  EXPECT_TRUE(query.matches(blocked));
  EXPECT_FALSE(query.matches(freed));
  EXPECT_FALSE(query.matches(blocker));
  EXPECT_FALSE(q(QStringLiteral("status:todo")).usesBlocked());
}

TEST(TaskQueryPlanning, MyTagsAndMyLayer) {
  Task t = mk(QStringLiteral("T"));
  t.local.tags = {LocalTag{QStringLiteral("after-release"), QString()}};
  t.local.notes = QStringLiteral("tried a smaller pool");
  const Task plain = mk(QStringLiteral("P"));
  EXPECT_TRUE(q(QStringLiteral("#after-release")).matches(t));
  EXPECT_FALSE(q(QStringLiteral("#after-release")).matches(plain));
  EXPECT_TRUE(q(QStringLiteral("has:notes")).matches(t));
  EXPECT_FALSE(q(QStringLiteral("has:draft")).matches(t));
  t.local.commentDraft = QStringLiteral("LGTM");
  EXPECT_TRUE(q(QStringLiteral("has:draft")).matches(t));
  EXPECT_TRUE(q(QStringLiteral("has:nothing")).unknownClauses().contains(QStringLiteral("has:nothing")));
  for(const char* f : {"scheduled", "estimate", "branch", "has"}) {
    EXPECT_TRUE(heap::query::queryFields().contains(QLatin1String(f))) << f;
  }
}
