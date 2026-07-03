#include "query/QueryParser.h"

#include <gtest/gtest.h>

using heap::query::Op;
using heap::query::ParsedQuery;
using heap::query::QueryParser;

TEST(QueryParser, EmptyIsNotOk) {
  const ParsedQuery q = QueryParser::parse(QString());
  EXPECT_FALSE(q.ok);
  EXPECT_TRUE(q.conditions.isEmpty());
  EXPECT_EQ(q.limit, 50);  // default
}

TEST(QueryParser, SingleEq) {
  const ParsedQuery q = QueryParser::parse(QStringLiteral("status:blocked"));
  ASSERT_TRUE(q.ok);
  ASSERT_EQ(q.conditions.size(), 1);
  EXPECT_EQ(q.conditions.at(0).field, QString("status"));
  EXPECT_EQ(q.conditions.at(0).op, Op::Eq);
  ASSERT_EQ(q.conditions.at(0).values.size(), 1);
  EXPECT_EQ(q.conditions.at(0).values.at(0), QString("blocked"));
}

TEST(QueryParser, CommaListBecomesIn) {
  const ParsedQuery q = QueryParser::parse(QStringLiteral("priority:P0,P1"));
  ASSERT_EQ(q.conditions.size(), 1);
  EXPECT_EQ(q.conditions.at(0).op, Op::In);
  ASSERT_EQ(q.conditions.at(0).values.size(), 2);
  EXPECT_EQ(q.conditions.at(0).values.at(0), QString("P0"));
  EXPECT_EQ(q.conditions.at(0).values.at(1), QString("P1"));
}

TEST(QueryParser, ComparisonOperators) {
  EXPECT_EQ(QueryParser::parse(QStringLiteral("deadline:<7d")).conditions.at(0).op, Op::Lt);
  EXPECT_EQ(QueryParser::parse(QStringLiteral("deadline:<=7d")).conditions.at(0).op, Op::Le);
  EXPECT_EQ(QueryParser::parse(QStringLiteral("deadline:>7d")).conditions.at(0).op, Op::Gt);
  EXPECT_EQ(QueryParser::parse(QStringLiteral("deadline:>=7d")).conditions.at(0).op, Op::Ge);
  // The operator is stripped from the value.
  EXPECT_EQ(QueryParser::parse(QStringLiteral("deadline:<7d")).conditions.at(0).values.at(0), QString("7d"));
}

TEST(QueryParser, MentionStripsAt) {
  const ParsedQuery q = QueryParser::parse(QStringLiteral("mention:@oleg"));
  ASSERT_EQ(q.conditions.size(), 1);
  EXPECT_EQ(q.conditions.at(0).field, QString("mention"));
  EXPECT_EQ(q.conditions.at(0).values.at(0), QString("oleg"));
}

TEST(QueryParser, MultipleClausesAnded) {
  const ParsedQuery q = QueryParser::parse(QStringLiteral("status:blocked priority:P0,P1 profile:lte-core"));
  ASSERT_EQ(q.conditions.size(), 3);
  EXPECT_EQ(q.conditions.at(0).field, QString("status"));
  EXPECT_EQ(q.conditions.at(1).field, QString("priority"));
  EXPECT_EQ(q.conditions.at(2).field, QString("profile"));
}

TEST(QueryParser, SortAscAndDesc) {
  const ParsedQuery a = QueryParser::parse(QStringLiteral("sort:deadline"));
  EXPECT_TRUE(a.ok);
  EXPECT_EQ(a.orderBy, QString("deadline"));
  EXPECT_FALSE(a.orderDesc);

  const ParsedQuery d = QueryParser::parse(QStringLiteral("sort:-deadline"));
  EXPECT_EQ(d.orderBy, QString("deadline"));
  EXPECT_TRUE(d.orderDesc);
}

TEST(QueryParser, LimitParsed) {
  const ParsedQuery q = QueryParser::parse(QStringLiteral("status:done limit:20"));
  EXPECT_EQ(q.limit, 20);
  EXPECT_EQ(q.conditions.size(), 1);
}

TEST(QueryParser, LimitInvalidIgnored) {
  const ParsedQuery q = QueryParser::parse(QStringLiteral("limit:abc"));
  EXPECT_EQ(q.limit, 50);   // default kept
  EXPECT_FALSE(q.ok);       // nothing recognized
}

TEST(QueryParser, UnknownFieldSkipped) {
  const ParsedQuery q = QueryParser::parse(QStringLiteral("wibble:x status:done"));
  ASSERT_EQ(q.conditions.size(), 1);
  EXPECT_EQ(q.conditions.at(0).field, QString("status"));
}

TEST(QueryParser, MalformedTokensSkipped) {
  const ParsedQuery q = QueryParser::parse(QStringLiteral("noColon status: :novalue status:open"));
  ASSERT_EQ(q.conditions.size(), 1);
  EXPECT_EQ(q.conditions.at(0).values.at(0), QString("open"));
}

TEST(QueryParser, CaseInsensitiveField) {
  const ParsedQuery q = QueryParser::parse(QStringLiteral("STATUS:done"));
  ASSERT_EQ(q.conditions.size(), 1);
  EXPECT_EQ(q.conditions.at(0).field, QString("status"));
}
