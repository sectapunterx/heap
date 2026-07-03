#include "integrations/StatusMap.h"

#include <QHash>
#include <QString>

#include <gtest/gtest.h>

using heap::integrations::StatusMap;

// ─── defaultColumn ────────────────────────────────────────────────────

TEST(StatusMap, DefaultColumnKnownStatuses) {
  EXPECT_EQ(StatusMap::defaultColumn(QStringLiteral("To Do")), QString("todo"));
  EXPECT_EQ(StatusMap::defaultColumn(QStringLiteral("In Progress")), QString("prog"));
  EXPECT_EQ(StatusMap::defaultColumn(QStringLiteral("In Review")), QString("review"));
  EXPECT_EQ(StatusMap::defaultColumn(QStringLiteral("Blocked")), QString("blocked"));
  EXPECT_EQ(StatusMap::defaultColumn(QStringLiteral("Done")), QString("done"));
  EXPECT_EQ(StatusMap::defaultColumn(QStringLiteral("Backlog")), QString("backlog"));
}

TEST(StatusMap, DefaultColumnCaseAndWhitespaceInsensitive) {
  EXPECT_EQ(StatusMap::defaultColumn(QStringLiteral("  in progress  ")), QString("prog"));
  EXPECT_EQ(StatusMap::defaultColumn(QStringLiteral("CLOSED")), QString("done"));
  EXPECT_EQ(StatusMap::defaultColumn(QStringLiteral("Merged")), QString("done"));
}

TEST(StatusMap, DefaultColumnUnknownIsEmpty) {
  EXPECT_TRUE(StatusMap::defaultColumn(QStringLiteral("Wibble")).isEmpty());
  EXPECT_TRUE(StatusMap::defaultColumn(QString()).isEmpty());
}

// ─── column (overrides + fallback) ────────────────────────────────────

TEST(StatusMap, ColumnUsesBuiltinThenFallback) {
  EXPECT_EQ(StatusMap::column(QStringLiteral("In Review")), QString("review"));
  // Unknown → default fallback "todo".
  EXPECT_EQ(StatusMap::column(QStringLiteral("Wibble")), QString("todo"));
  // Unknown → explicit fallback.
  EXPECT_EQ(StatusMap::column(QStringLiteral("Wibble"), {}, QStringLiteral("backlog")), QString("backlog"));
}

TEST(StatusMap, ColumnOverrideWins) {
  QHash<QString, QString> ov;
  ov.insert(QStringLiteral("In Review"), QStringLiteral("prog"));  // team maps review→prog
  EXPECT_EQ(StatusMap::column(QStringLiteral("In Review"), ov), QString("prog"));
  // Override matched case-insensitively.
  EXPECT_EQ(StatusMap::column(QStringLiteral("in review"), ov), QString("prog"));
  // A status not in the override falls back to the built-in table.
  EXPECT_EQ(StatusMap::column(QStringLiteral("Done"), ov), QString("done"));
}

TEST(StatusMap, ColumnOverrideCanMapUnknownStatus) {
  QHash<QString, QString> ov;
  ov.insert(QStringLiteral("Awaiting QA"), QStringLiteral("review"));
  EXPECT_EQ(StatusMap::column(QStringLiteral("Awaiting QA"), ov), QString("review"));
}

// ─── priority ─────────────────────────────────────────────────────────

TEST(StatusMap, PriorityMapping) {
  EXPECT_EQ(StatusMap::priority(QStringLiteral("Highest")), QString("P0"));
  EXPECT_EQ(StatusMap::priority(QStringLiteral("High")), QString("P1"));
  EXPECT_EQ(StatusMap::priority(QStringLiteral("Medium")), QString("P2"));
  EXPECT_EQ(StatusMap::priority(QStringLiteral("Low")), QString("P3"));
  EXPECT_EQ(StatusMap::priority(QStringLiteral("Lowest")), QString("P3"));
  EXPECT_EQ(StatusMap::priority(QStringLiteral("critical")), QString("P0"));
}

TEST(StatusMap, PriorityUnknownFallback) {
  EXPECT_EQ(StatusMap::priority(QStringLiteral("Sometime")), QString("P2"));
  EXPECT_EQ(StatusMap::priority(QStringLiteral("Sometime"), QStringLiteral("P3")), QString("P3"));
  EXPECT_EQ(StatusMap::priority(QString()), QString("P2"));
}
