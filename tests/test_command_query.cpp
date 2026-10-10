// The command line's input (APP-267): the language quick capture speaks,
// read as search clauses plus the words left over.
#include "chrono/ChronoParser.h"
#include "query/CommandQuery.h"

#include <QDate>
#include <QDateTime>
#include <QLocale>
#include <QTime>
#include <QVariantMap>

#include <gtest/gtest.h>

using heap::query::CommandQuery;
using heap::query::parseCommandLine;
using heap::query::statusByPrefix;

namespace {

const QDateTime kNow(QDate(2026, 10, 7), QTime(10, 0));  // Wednesday

QVariantList statuses() {
  return {QVariantMap{{"id", "todo"}, {"name", "К выполнению"}},
          QVariantMap{{"id", "in-progress"}, {"name", "В работе"}},
          QVariantMap{{"id", "blocked"}, {"name", "Заблокировано"}},
          QVariantMap{{"id", "review"}, {"name", "Ревью"}},
          QVariantMap{{"id", "done"}, {"name", "Готово"}}};
}

class CommandLine : public ::testing::Test {
 protected:
  heap::chrono::ChronoParser chrono{QLocale(QLocale::Russian, QLocale::Russia)};

  CommandQuery p(const QString& text, bool scheduled = false) {
    return parseCommandLine(text, statuses(), &chrono, kNow, scheduled);
  }
};

}  // namespace

TEST(CommandStatus, ByTheStartOfAWord) {
  EXPECT_EQ(statusByPrefix(QStringLiteral("заблок"), statuses()), QStringLiteral("blocked"));
  EXPECT_EQ(statusByPrefix(QStringLiteral("ревью"), statuses()), QStringLiteral("review"));
  EXPECT_EQ(statusByPrefix(QStringLiteral("работ"), statuses()), QStringLiteral("in-progress"));
  EXPECT_EQ(statusByPrefix(QStringLiteral("гот"), statuses()), QStringLiteral("done"));
  EXPECT_TRUE(statusByPrefix(QStringLiteral("за"), statuses()).isEmpty()) << "two letters are a word";
  EXPECT_TRUE(statusByPrefix(QStringLiteral("оформ"), statuses()).isEmpty());
}

TEST_F(CommandLine, StatusPriorityAndWords) {
  const CommandQuery q = p(QStringLiteral("заблок p0 оформ"));
  ASSERT_EQ(q.tokens.size(), 2);
  EXPECT_EQ(q.tokens[0].kind, QStringLiteral("status"));
  EXPECT_EQ(q.tokens[0].clause, QStringLiteral("status:blocked"));
  EXPECT_EQ(q.tokens[0].value, QStringLiteral("Заблокировано"));
  EXPECT_EQ(q.tokens[1].kind, QStringLiteral("priority"));
  EXPECT_EQ(q.tokens[1].clause, QStringLiteral("priority:P0"));
  EXPECT_EQ(q.text, QStringLiteral("оформ"));
  EXPECT_EQ(q.query(), QStringLiteral("status:blocked priority:P0 оформ"));
}

TEST_F(CommandLine, DeadlineWordMakesADueClause) {
  const CommandQuery q = p(QStringLiteral("отчёт до пятницы"));
  ASSERT_EQ(q.tokens.size(), 1);
  EXPECT_EQ(q.tokens[0].kind, QStringLiteral("due"));
  EXPECT_EQ(q.tokens[0].clause, QStringLiteral("due:<=2026-10-09"));
  EXPECT_EQ(q.text, QStringLiteral("отчёт"));
}

TEST_F(CommandLine, AWhenDateIsAFilterOnlyWhereTheSearchKnowsOne) {
  const CommandQuery without = p(QStringLiteral("созвон завтра"));
  EXPECT_TRUE(without.tokens.isEmpty());
  EXPECT_EQ(without.text, QStringLiteral("созвон завтра"));
  const CommandQuery with = p(QStringLiteral("созвон завтра"), true);
  ASSERT_EQ(with.tokens.size(), 1);
  EXPECT_EQ(with.tokens[0].clause, QStringLiteral("scheduled:2026-10-08"));
}

TEST_F(CommandLine, TagTicketAndClause) {
  const CommandQuery q = p(QStringLiteral("#Auth app-101 is:open"));
  ASSERT_EQ(q.tokens.size(), 3);
  EXPECT_EQ(q.tokens[0].clause, QStringLiteral("tag:auth"));
  EXPECT_EQ(q.tokens[1].kind, QStringLiteral("ticket"));
  EXPECT_EQ(q.tokens[1].clause, QStringLiteral("APP-101"));
  EXPECT_EQ(q.tokens[2].clause, QStringLiteral("is:open"));
  EXPECT_TRUE(q.text.isEmpty());
}

TEST_F(CommandLine, GreaterThanIsCommandsOnly) {
  const CommandQuery q = p(QStringLiteral("> тема"));
  EXPECT_TRUE(q.commandsOnly);
  EXPECT_EQ(q.text, QStringLiteral("тема"));
  EXPECT_TRUE(q.tokens.isEmpty());
}

TEST_F(CommandLine, TwoColumnsAreOneClause) {
  const CommandQuery q = p(QStringLiteral("заблок ревью"));
  EXPECT_EQ(q.query(), QStringLiteral("status:blocked,review"));
}

TEST_F(CommandLine, PlainWordsStayWords) {
  const CommandQuery q = p(QStringLiteral("логин падает"));
  EXPECT_TRUE(q.tokens.isEmpty());
  EXPECT_EQ(q.query(), QStringLiteral("логин падает"));
}
