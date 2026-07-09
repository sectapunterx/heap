#include "sync/SyncSerializer.h"

#include <QByteArray>
#include <QColor>
#include <QDate>
#include <QDateTime>

#include <gtest/gtest.h>

#include <algorithm>

using heap::sync::SyncSerializer;

namespace {

Task makeTask(const QString& id, const QString& title) {
  Task t;
  t.id = id;
  t.title = title;
  t.desc = QStringLiteral("desc of ") + id;
  t.priority = QStringLiteral("P1");
  t.status = QStringLiteral("prog");
  t.dueAt = QDateTime(QDate(2026, 7, 15), QTime(0, 0));
  t.scheduledAt = t.dueAt;
  t.branch = QStringLiteral("fix/") + id;
  t.statusChangedAt = QDateTime(QDate(2026, 7, 1), QTime(14, 30));
  t.archived = false;
  return t;
}

Profile makeProfile() {
  Profile p;
  p.id = QStringLiteral("lte-core");
  p.name = QStringLiteral("LTE Core");
  p.color = QStringLiteral("#5cc2dd");
  p.createdAt = QDateTime(QDate(2026, 1, 2), QTime(9, 0));
  // Deliberately out of id order to exercise stable sorting.
  p.tasks = {makeTask("T-3", "third"), makeTask("T-1", "first"), makeTask("T-2", "second")};

  Person a;
  a.id = QStringLiteral("a.ivanov");
  a.name = QStringLiteral("Anton Ivanov");
  a.role = QStringLiteral("dev");
  a.question = QStringLiteral("review?");
  a.state = QStringLiteral("pinged");
  a.color = QColor("#d97a6c");
  p.people = {a};

  p.statuses = QVariantList{
      QVariantMap{{"id", "prog"}, {"name", "In progress"}, {"color", "#83a598"}},
      QVariantMap{{"id", "done"}, {"name", "Done"}, {"color", "#b8bb26"}},
  };
  p.docsState = QStringLiteral("{\"docs\":{}}");
  p.notesState = QStringLiteral("# Notes\n- one\n- two");
  return p;
}

}  // namespace

// ─── Round-trip idempotency ───

TEST(SyncSerializer, ProfileRoundTripPreservesFields) {
  const Profile p = makeProfile();
  const QByteArray json = SyncSerializer::serializeProfile(p);
  const auto back = SyncSerializer::deserializeProfile(json);
  ASSERT_TRUE(back.has_value());

  EXPECT_EQ(back->id, p.id);
  EXPECT_EQ(back->name, p.name);
  EXPECT_EQ(back->color, p.color);
  EXPECT_EQ(back->createdAt, p.createdAt);
  EXPECT_EQ(back->tasks.size(), 3);
  EXPECT_EQ(back->people.size(), 1);
  EXPECT_EQ(back->statuses.size(), 2);
  EXPECT_EQ(back->docsState, p.docsState);
  EXPECT_EQ(back->notesState, p.notesState);
}

TEST(SyncSerializer, TaskFieldsSurviveRoundTrip) {
  const Profile p = makeProfile();
  const auto back = SyncSerializer::deserializeProfile(SyncSerializer::serializeProfile(p));
  ASSERT_TRUE(back.has_value());
  // Tasks come back sorted by id: T-1, T-2, T-3.
  const Task& first = back->tasks.at(0);
  EXPECT_EQ(first.id, QString("T-1"));
  EXPECT_EQ(first.title, QString("first"));
  EXPECT_EQ(first.priority, QString("P1"));
  EXPECT_EQ(first.dueAt, QDateTime(QDate(2026, 7, 15), QTime(0, 0)));
  EXPECT_EQ(first.statusChangedAt, QDateTime(QDate(2026, 7, 1), QTime(14, 30)));
  EXPECT_FALSE(first.archived);
  EXPECT_EQ(first.branch, QString("fix/T-1"));
}

TEST(SyncSerializer, PersonColorSurvivesRoundTrip) {
  const Profile p = makeProfile();
  const auto back = SyncSerializer::deserializeProfile(SyncSerializer::serializeProfile(p));
  ASSERT_TRUE(back.has_value());
  ASSERT_EQ(back->people.size(), 1);
  EXPECT_EQ(back->people.at(0).color.name(QColor::HexRgb), QString("#d97a6c"));
}

TEST(SyncSerializer, SerializeIsIdempotent) {
  const Profile p = makeProfile();
  const QByteArray once = SyncSerializer::serializeProfile(p);
  const auto back = SyncSerializer::deserializeProfile(once);
  ASSERT_TRUE(back.has_value());
  const QByteArray twice = SyncSerializer::serializeProfile(*back);
  EXPECT_EQ(once, twice);
}

// ─── Stable ordering: byte output must not depend on vector order ───

TEST(SyncSerializer, StableOrderingIndependentOfTaskVectorOrder) {
  Profile a = makeProfile();  // tasks: T-3, T-1, T-2
  Profile b = makeProfile();
  // Reverse b's task vector — same logical content, different order.
  std::reverse(b.tasks.begin(), b.tasks.end());
  EXPECT_EQ(SyncSerializer::serializeProfile(a), SyncSerializer::serializeProfile(b));
}

TEST(SyncSerializer, TasksEmittedSortedById) {
  const Profile p = makeProfile();
  const QByteArray json = SyncSerializer::serializeProfile(p);
  const QString s = QString::fromUtf8(json);
  const int i1 = s.indexOf(QStringLiteral("\"T-1\""));
  const int i2 = s.indexOf(QStringLiteral("\"T-2\""));
  const int i3 = s.indexOf(QStringLiteral("\"T-3\""));
  ASSERT_GE(i1, 0);
  ASSERT_GE(i2, 0);
  ASSERT_GE(i3, 0);
  EXPECT_LT(i1, i2);
  EXPECT_LT(i2, i3);
}

// ─── Events file ───

TEST(SyncSerializer, EventsRoundTrip) {
  CalEvent e;
  e.id = QStringLiteral("ev-1");
  e.title = QStringLiteral("Standup");
  e.type = QStringLiteral("standup");
  e.start = 10.0;
  e.end = 10.5;
  e.attendees = QStringLiteral("team");
  e.date = QDate(2026, 7, 2);
  e.taskId = QStringLiteral("T-1");
  e.profileId = QStringLiteral("lte-core");
  e.context = QStringLiteral("daily");

  const QByteArray json = SyncSerializer::serializeEvents({e});
  const QVector<CalEvent> back = SyncSerializer::deserializeEvents(json);
  ASSERT_EQ(back.size(), 1);
  EXPECT_EQ(back.at(0).id, QString("ev-1"));
  EXPECT_DOUBLE_EQ(back.at(0).start, 10.0);
  EXPECT_DOUBLE_EQ(back.at(0).end, 10.5);
  EXPECT_EQ(back.at(0).date, QDate(2026, 7, 2));
  EXPECT_EQ(back.at(0).taskId, QString("T-1"));
}

// ─── Malformed input ───

TEST(SyncSerializer, DeserializeRejectsNonObject) {
  EXPECT_FALSE(SyncSerializer::deserializeProfile(QByteArray("[]")).has_value());
  EXPECT_FALSE(SyncSerializer::deserializeProfile(QByteArray("not json")).has_value());
  EXPECT_TRUE(SyncSerializer::deserializeEvents(QByteArray("garbage")).isEmpty());
}
