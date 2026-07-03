#include "sync/JsonMerger.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <gtest/gtest.h>

using heap::sync::JsonMerger;
using heap::sync::MergeResult;

namespace {

QJsonObject O(const char* json) {
  return QJsonDocument::fromJson(QByteArray(json)).object();
}

}  // namespace

// ─── scalars ──────────────────────────────────────────────────────────

TEST(JsonMerger, NoChange) {
  const QJsonObject b = O(R"({"a":1,"b":"x"})");
  const MergeResult m = JsonMerger::merge(b, b, b);
  EXPECT_TRUE(m.ok);
  EXPECT_EQ(m.merged, b);
}

TEST(JsonMerger, LocalOnlyEditTaken) {
  const QJsonObject b = O(R"({"a":1})");
  const MergeResult m = JsonMerger::merge(b, O(R"({"a":2})"), b);
  EXPECT_TRUE(m.ok);
  EXPECT_EQ(m.merged.value("a").toInt(), 2);
}

TEST(JsonMerger, RemoteOnlyEditTaken) {
  const QJsonObject b = O(R"({"a":1})");
  const MergeResult m = JsonMerger::merge(b, b, O(R"({"a":9})"));
  EXPECT_TRUE(m.ok);
  EXPECT_EQ(m.merged.value("a").toInt(), 9);
}

TEST(JsonMerger, EditEditConflictKeepsLocal) {
  const QJsonObject b = O(R"({"a":1})");
  const MergeResult m = JsonMerger::merge(b, O(R"({"a":2})"), O(R"({"a":3})"));
  EXPECT_FALSE(m.ok);
  ASSERT_EQ(m.conflicts.size(), 1);
  EXPECT_EQ(m.conflicts.at(0).path, QString("/a"));
  EXPECT_EQ(m.merged.value("a").toInt(), 2);  // local kept
}

TEST(JsonMerger, AddAddSameNoConflict) {
  const QJsonObject b = O(R"({})");
  const MergeResult m = JsonMerger::merge(b, O(R"({"k":"v"})"), O(R"({"k":"v"})"));
  EXPECT_TRUE(m.ok);
  EXPECT_EQ(m.merged.value("k").toString(), QString("v"));
}

TEST(JsonMerger, AddAddConflict) {
  const QJsonObject b = O(R"({})");
  const MergeResult m = JsonMerger::merge(b, O(R"({"k":"l"})"), O(R"({"k":"r"})"));
  EXPECT_FALSE(m.ok);
  EXPECT_EQ(m.merged.value("k").toString(), QString("l"));
}

TEST(JsonMerger, RemoteDeleteLocalUnchangedDrops) {
  const QJsonObject b = O(R"({"a":1,"b":2})");
  const MergeResult m = JsonMerger::merge(b, b, O(R"({"a":1})"));
  EXPECT_TRUE(m.ok);
  EXPECT_FALSE(m.merged.contains("b"));
}

TEST(JsonMerger, EditDeleteConflictKeepsLocal) {
  const QJsonObject b = O(R"({"a":1,"b":2})");
  const MergeResult m = JsonMerger::merge(b, O(R"({"a":1,"b":5})"), O(R"({"a":1})"));
  EXPECT_FALSE(m.ok);
  EXPECT_EQ(m.merged.value("b").toInt(), 5);
}

TEST(JsonMerger, NestedObjectRecurseMergesBothFields) {
  const QJsonObject b = O(R"({"o":{"x":1,"y":1}})");
  const MergeResult m = JsonMerger::merge(b, O(R"({"o":{"x":2,"y":1}})"), O(R"({"o":{"x":1,"y":3}})"));
  EXPECT_TRUE(m.ok);
  EXPECT_EQ(m.merged.value("o").toObject().value("x").toInt(), 2);
  EXPECT_EQ(m.merged.value("o").toObject().value("y").toInt(), 3);
}

TEST(JsonMerger, CreatedAtEarliestWinsNoConflict) {
  const QJsonObject b = O(R"({"createdAt":"2026-05-01T00:00"})");
  const MergeResult m = JsonMerger::merge(
      b, O(R"({"createdAt":"2026-04-01T00:00"})"), O(R"({"createdAt":"2026-06-01T00:00"})"));
  EXPECT_TRUE(m.ok);
  EXPECT_EQ(m.merged.value("createdAt").toString(), QString("2026-04-01T00:00"));
}

// ─── arrays merged by id ──────────────────────────────────────────────

TEST(JsonMerger, ArrayAddOnEachSideMergesById) {
  const QJsonObject b = O(R"({"tasks":[{"id":"T1","t":"a"}]})");
  const QJsonObject l = O(R"({"tasks":[{"id":"T1","t":"a"},{"id":"T2","t":"b"}]})");
  const QJsonObject r = O(R"({"tasks":[{"id":"T1","t":"a"},{"id":"T3","t":"c"}]})");
  const MergeResult m = JsonMerger::merge(b, l, r);
  EXPECT_TRUE(m.ok);
  const QJsonArray a = m.merged.value("tasks").toArray();
  ASSERT_EQ(a.size(), 3);
  EXPECT_EQ(a.at(0).toObject().value("id").toString(), QString("T1"));
  EXPECT_EQ(a.at(1).toObject().value("id").toString(), QString("T2"));
  EXPECT_EQ(a.at(2).toObject().value("id").toString(), QString("T3"));
}

TEST(JsonMerger, ArrayElementLocalOnlyEdit) {
  const QJsonObject b = O(R"({"tasks":[{"id":"T1","t":"a"}]})");
  const QJsonObject l = O(R"({"tasks":[{"id":"T1","t":"b"}]})");
  const MergeResult m = JsonMerger::merge(b, l, b);
  EXPECT_TRUE(m.ok);
  EXPECT_EQ(m.merged.value("tasks").toArray().at(0).toObject().value("t").toString(), QString("b"));
}

TEST(JsonMerger, ArrayElementBothEditLwwByUpdatedAt) {
  const QJsonObject b = O(R"({"tasks":[{"id":"T1","t":"a","updatedAt":"2026-01-01T00:00"}]})");
  const QJsonObject l = O(R"({"tasks":[{"id":"T1","t":"local","updatedAt":"2026-07-01T10:00"}]})");
  const QJsonObject r = O(R"({"tasks":[{"id":"T1","t":"remote","updatedAt":"2026-07-02T10:00"}]})");
  const MergeResult m = JsonMerger::merge(b, l, r);
  EXPECT_TRUE(m.ok);  // LWW resolves it
  EXPECT_EQ(m.merged.value("tasks").toArray().at(0).toObject().value("t").toString(), QString("remote"));
}

TEST(JsonMerger, ArrayElementBothEditNoTimestampConflict) {
  const QJsonObject b = O(R"({"tasks":[{"id":"T1","t":"a"}]})");
  const QJsonObject l = O(R"({"tasks":[{"id":"T1","t":"local"}]})");
  const QJsonObject r = O(R"({"tasks":[{"id":"T1","t":"remote"}]})");
  const MergeResult m = JsonMerger::merge(b, l, r);
  EXPECT_FALSE(m.ok);
  ASSERT_EQ(m.conflicts.size(), 1);
  EXPECT_EQ(m.conflicts.at(0).path, QString("/tasks/T1"));
  EXPECT_EQ(m.merged.value("tasks").toArray().at(0).toObject().value("t").toString(), QString("local"));
}

TEST(JsonMerger, ArrayDeleteVsUnchangedDrops) {
  const QJsonObject b = O(R"({"tasks":[{"id":"T1"},{"id":"T2"}]})");
  const QJsonObject l = O(R"({"tasks":[{"id":"T1"}]})");  // local dropped T2
  const MergeResult m = JsonMerger::merge(b, l, b);       // remote unchanged
  EXPECT_TRUE(m.ok);
  const QJsonArray a = m.merged.value("tasks").toArray();
  ASSERT_EQ(a.size(), 1);
  EXPECT_EQ(a.at(0).toObject().value("id").toString(), QString("T1"));
}

TEST(JsonMerger, ArrayEditVsDeleteConflict) {
  const QJsonObject b = O(R"({"tasks":[{"id":"T1","t":"a"}]})");
  const QJsonObject l = O(R"({"tasks":[{"id":"T1","t":"edited"}]})");  // local edits
  const QJsonObject r = O(R"({"tasks":[]})");                          // remote deletes
  const MergeResult m = JsonMerger::merge(b, l, r);
  EXPECT_FALSE(m.ok);
  ASSERT_EQ(m.conflicts.size(), 1);
  EXPECT_EQ(m.merged.value("tasks").toArray().size(), 1);  // local kept
}

// ─── opaque (non-id) arrays ───────────────────────────────────────────

TEST(JsonMerger, OpaqueArrayLocalOnlyChange) {
  const QJsonObject b = O(R"({"labels":["a","b"]})");
  const QJsonObject l = O(R"({"labels":["a","b","c"]})");
  const MergeResult m = JsonMerger::merge(b, l, b);
  EXPECT_TRUE(m.ok);
  EXPECT_EQ(m.merged.value("labels").toArray().size(), 3);
}

TEST(JsonMerger, OpaqueArrayBothChangeConflict) {
  const QJsonObject b = O(R"({"labels":["a"]})");
  const QJsonObject l = O(R"({"labels":["a","l"]})");
  const QJsonObject r = O(R"({"labels":["a","r"]})");
  const MergeResult m = JsonMerger::merge(b, l, r);
  EXPECT_FALSE(m.ok);
  EXPECT_EQ(m.merged.value("labels").toArray().size(), 2);  // local kept
}
