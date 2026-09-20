// Lossless serialization guard (HEAP-131).
//
// Two serializers write Task/CalEvent: heap::state (the live save + export path
// behind AppController::saveStateNow) and heap::sync::SyncSerializer (the sync
// transport). A field that only one of them knows about is a field that gets
// silently dropped. This suite pins both:
//
//   1. A property test: 1000 randomized Tasks and CalEvents must satisfy
//      x == fromJson(toJson(x)) through EACH serializer.
//   2. A field-count guard: makeFullTask/makeFullEvent set every declared field
//      to a non-default value, and the emitted JSON must carry one key per
//      field. Add a field without serializing it and this fails. Add a field
//      without extending the fixtures and the static_asserts in
//      src/StateSerializer.cpp and src/sync/SyncSerializer.cpp fail the build.

#include "FieldCount.h"
#include "Models.h"
#include "StateSerializer.h"

#include "sync/SyncSerializer.h"

#include <QDate>
#include <QDateTime>
#include <QJsonObject>
#include <QTime>

#include <gtest/gtest.h>

#include <random>

namespace {

// Every declared field of ExternalMeta, set to something that is not its
// default — including a comment count, whose default is -1 rather than 0.
ExternalMeta makeFullMeta() {
  ExternalMeta m;
  m.author = QStringLiteral("grace");
  m.issueType = QStringLiteral("Bug");
  m.project = QStringLiteral("sectapunterx/heap");
  m.milestone = QStringLiteral("v0.5.0");
  m.commentCount = 7;
  m.createdAt = QDateTime(QDate(2026, 6, 1), QTime(8, 15, 30, 500));
  m.updatedAt = QDateTime(QDate(2026, 7, 8), QTime(11, 45, 10, 125));
  m.dueAt = QDateTime(QDate(2026, 7, 11), QTime(16, 0, 0, 750));
  m.crossProject = true;
  return m;
}

// Every declared field of Task, set to something that is not its default.
Task makeFullTask() {
  Task t;
  t.id = QStringLiteral("HEAP-104");
  t.title = QStringLiteral("Harden the task data model");
  t.desc = QStringLiteral("lossless, time-aware persistence");
  t.priority = QStringLiteral("P0");
  t.status = QStringLiteral("prog");
  t.scheduledAt = QDateTime(QDate(2026, 7, 10), QTime(9, 0, 0, 250));
  t.dueAt = QDateTime(QDate(2026, 7, 11), QTime(16, 0, 0, 750));
  t.hasTime = true;
  t.branch = QStringLiteral("heap-104-lossless-task-model");
  t.statusChangedAt = QDateTime(QDate(2026, 7, 9), QTime(14, 30, 5, 125));
  t.archived = true;
  t.trackedSeconds = 4242;
  t.timerStartedAt = QDateTime(QDate(2026, 7, 9), QTime(15, 0, 1, 5));
  t.recurrence = QStringLiteral("every:weekday");
  t.externalId = QStringLiteral("104");
  t.externalUrl = QStringLiteral("https://github.com/sectapunterx/heap/issues/104");
  t.externalProvider = QStringLiteral("github");
  t.labels = {Label{QStringLiteral("infra"), QStringLiteral("#5cc2dd")}, Label{QStringLiteral("trust"), QString()}};
  t.estimateMinutes = 480;
  t.someday = true;
  t.assignee = QStringLiteral("sectapunterx");
  t.externalMeta = makeFullMeta();
  // Schema v5. A fractional rank on purpose: the midpoint of two neighbours is
  // what a drop between cards produces, and it has to survive the round trip
  // exactly or the card moves on the next launch.
  t.rank = 1536.5;
  t.links = {TaskLink{QStringLiteral("blocks"), QStringLiteral("HEAP-105")},
             TaskLink{QStringLiteral("blocks"), QStringLiteral("HEAP-106")}};
  return t;
}

CalEvent makeFullEvent() {
  CalEvent e;
  e.id = QStringLiteral("ev-1");
  e.title = QStringLiteral("Design review");
  e.type = QStringLiteral("sync");
  e.start = 10.5;
  e.end = 11.25;
  e.attendees = QStringLiteral("Ann, Bob");
  e.date = QDate(2026, 7, 10);
  e.taskId = QStringLiteral("HEAP-104");
  e.profileId = QStringLiteral("default");
  e.context = QStringLiteral("heap");
  e.allDay = true;
  e.endDate = QDate(2026, 7, 12);
  return e;
}

// Deterministic generator: the same seed produces the same 1000 cases on every
// platform, so a CI failure is reproducible locally.
class Gen {
 public:
  explicit Gen(quint32 seed) : rng_(seed) {
  }

  bool boolean() {
    return pick(0, 1) == 1;
  }

  int pick(int lo, int hi) {
    return std::uniform_int_distribution<int>(lo, hi)(rng_);
  }

  QString text() {
    static const QStringList kWords = {QStringLiteral(""),
                                       QStringLiteral("a"),
                                       QStringLiteral("ship it"),
                                       QStringLiteral("émoji ✅日本語"),
                                       QStringLiteral("quote\"and\\slash"),
                                       QStringLiteral("line\nbreak")};
    return kWords.at(pick(0, kWords.size() - 1));
  }

  // Milliseconds included: ISODateWithMs must carry them through.
  QDateTime dateTime(bool allowInvalid = true) {
    if(allowInvalid && pick(0, 3) == 0) {
      return {};
    }
    const QDate d(pick(1970, 2200), pick(1, 12), pick(1, 28));
    const QTime t(pick(0, 23), pick(0, 59), pick(0, 59), pick(0, 999));
    return QDateTime(d, t);
  }

  QDate date() {
    return pick(0, 3) == 0 ? QDate() : QDate(pick(1970, 2200), pick(1, 12), pick(1, 28));
  }

  Task task() {
    Task t;
    t.id = QStringLiteral("T-") + QString::number(pick(1, 10000));
    t.title = text();
    t.desc = text();
    t.priority = QStringLiteral("P") + QString::number(pick(0, 3));
    t.status = text();
    t.scheduledAt = dateTime();
    t.dueAt = dateTime();
    t.hasTime = boolean();
    t.branch = text();
    // Never invalid: taskFromJson heals a missing status stamp to "now", which
    // is deliberate (old files must not sort to the epoch) and unmatchable.
    t.statusChangedAt = dateTime(false);
    t.archived = boolean();
    t.trackedSeconds = pick(0, 100000);
    t.timerStartedAt = dateTime();
    t.recurrence = boolean() ? QStringLiteral("every:week") : QString();
    if(boolean()) {
      t.externalId = QString::number(pick(1, 999));
      t.externalUrl = QStringLiteral("https://example.invalid/") + t.externalId;
      t.externalProvider = QStringLiteral("gitlab");
    }
    const int labelCount = pick(0, 3);
    for(int i = 0; i < labelCount; ++i) {
      t.labels.append(Label{QStringLiteral("l") + QString::number(pick(1, 20)), boolean() ? QStringLiteral("#ff0000") : QString()});
    }
    t.estimateMinutes = pick(0, 5000);
    t.someday = boolean();
    t.assignee = text();
    // Half the cases carry tracker metadata, half leave it default, so both the
    // "omit the whole object" and the "write it out" paths get exercised.
    if(boolean()) {
      t.externalMeta.author = text();
      t.externalMeta.issueType = text();
      t.externalMeta.project = text();
      t.externalMeta.milestone = text();
      // -1 is the default and means "unknown"; it has to survive as itself.
      t.externalMeta.commentCount = pick(-1, 50);
      t.externalMeta.createdAt = dateTime();
      t.externalMeta.updatedAt = dateTime();
      t.externalMeta.dueAt = dateTime();
      t.externalMeta.crossProject = boolean();
    }
    // Ranks are fractional in practice — a drop between two cards is their
    // midpoint — so halves are generated, not whole numbers.
    t.rank = pick(0, 100000) / 2.0;
    const int linkCount = pick(0, 3);
    for(int i = 0; i < linkCount; ++i) {
      t.links.append(TaskLink{QStringLiteral("blocks"), QStringLiteral("T-") + QString::number(pick(1, 10000))});
    }
    return t;
  }

  CalEvent event() {
    CalEvent e;
    e.id = QStringLiteral("E-") + QString::number(pick(1, 10000));
    e.title = text();
    e.type = text();
    e.start = pick(0, 47) / 2.0;
    e.end = e.start + pick(1, 4) / 2.0;
    e.attendees = text();
    e.date = date();
    e.taskId = text();
    e.profileId = text();
    e.context = text();
    e.allDay = boolean();
    // Half the cases carry an end date, so both the single-day and the
    // multi-day shape go through every serializer.
    e.endDate = boolean() ? e.date.addDays(pick(1, 5)) : QDate();
    return e;
  }

 private:
  std::mt19937 rng_;
};

constexpr int kCases = 1000;

}  // namespace

// ── The compile-time half of the guard ──
// Mirrors the static_asserts inside both serializers. If the struct grows and
// only one serializer is updated, that serializer's own static_assert fires.
TEST(FieldCountGuard, TaskAndEventArityIsPinned) {
  EXPECT_EQ(heap::meta::fieldCount<Task>(), 24u);
  EXPECT_EQ(heap::meta::fieldCount<CalEvent>(), 12u);
}

// ExternalMeta is nested inside Task, so Task's own count stays 1 for the whole
// object — this is what stops a field added in there from being dropped.
TEST(FieldCountGuard, ExternalMetaArityIsPinned) {
  EXPECT_EQ(heap::meta::fieldCount<ExternalMeta>(), 9u);
}

// ── The runtime half: one emitted key per declared field ──
// The live serializer omits keys whose value is the default, so a task with
// every field set must emit exactly as many keys as the struct has fields.
TEST(FieldCountGuard, LiveSerializerEmitsAKeyForEveryTaskField) {
  const QJsonObject o = heap::state::taskToJson(makeFullTask());
  EXPECT_EQ(static_cast<std::size_t>(o.keys().size()), heap::meta::fieldCount<Task>())
      << "keys: " << o.keys().join(QStringLiteral(",")).toStdString();
}

TEST(FieldCountGuard, LiveSerializerEmitsAKeyForEveryEventField) {
  const QJsonObject o = heap::state::eventToJson(makeFullEvent());
  EXPECT_EQ(static_cast<std::size_t>(o.keys().size()), heap::meta::fieldCount<CalEvent>());
}

TEST(FieldCountGuard, SyncSerializerEmitsAKeyForEveryTaskField) {
  const QJsonObject o = heap::sync::SyncSerializer::taskToJson(makeFullTask());
  EXPECT_EQ(static_cast<std::size_t>(o.keys().size()), heap::meta::fieldCount<Task>())
      << "keys: " << o.keys().join(QStringLiteral(",")).toStdString();
}

TEST(FieldCountGuard, SyncSerializerEmitsAKeyForEveryEventField) {
  const QJsonObject o = heap::sync::SyncSerializer::eventToJson(makeFullEvent());
  EXPECT_EQ(static_cast<std::size_t>(o.keys().size()), heap::meta::fieldCount<CalEvent>());
}

// ── Fully-populated round trips ──

TEST(RoundTrip, FullTaskSurvivesLiveSerializer) {
  const Task t = makeFullTask();
  EXPECT_EQ(t, heap::state::taskFromJson(heap::state::taskToJson(t)));
}

TEST(RoundTrip, FullTaskSurvivesSyncSerializer) {
  const Task t = makeFullTask();
  EXPECT_EQ(t, heap::sync::SyncSerializer::taskFromJson(heap::sync::SyncSerializer::taskToJson(t)));
}

TEST(RoundTrip, FullEventSurvivesBothSerializers) {
  const CalEvent e = makeFullEvent();
  EXPECT_EQ(e, heap::state::eventFromJson(heap::state::eventToJson(e)));
  EXPECT_EQ(e, heap::sync::SyncSerializer::eventFromJson(heap::sync::SyncSerializer::eventToJson(e)));
}

// A running timer, a recurrence rule and an external id in one task.
TEST(RoundTrip, RunningTimerRecurrenceAndExternalIdAllSurvive) {
  Task t;
  t.id = QStringLiteral("X-1");
  t.statusChangedAt = QDateTime(QDate(2026, 1, 1), QTime(1, 2, 3));
  t.trackedSeconds = 61;
  t.timerStartedAt = QDateTime(QDate(2026, 1, 1), QTime(2, 0));
  t.recurrence = QStringLiteral("every:mon");
  t.externalId = QStringLiteral("PROJ-9");
  t.externalUrl = QStringLiteral("https://jira.invalid/browse/PROJ-9");
  t.externalProvider = QStringLiteral("jira");

  const Task live = heap::state::taskFromJson(heap::state::taskToJson(t));
  EXPECT_EQ(live.trackedSeconds, 61);
  EXPECT_EQ(live.timerStartedAt, t.timerStartedAt);
  EXPECT_EQ(live.recurrence, QString("every:mon"));
  EXPECT_EQ(live.externalId, QString("PROJ-9"));
  EXPECT_EQ(live, t);

  const Task synced = heap::sync::SyncSerializer::taskFromJson(heap::sync::SyncSerializer::taskToJson(t));
  EXPECT_EQ(synced, t);
}

// ── Tracker metadata (HEAP-117) ──

TEST(RoundTrip, LiveSerializerOmitsDefaultMetaEntirely) {
  // A locally-created task must serialize exactly as it did before HEAP-117.
  Task t;
  t.id = QStringLiteral("LOCAL-1");
  t.statusChangedAt = QDateTime(QDate(2026, 1, 1), QTime(1, 2, 3));
  const QJsonObject o = heap::state::taskToJson(t);
  EXPECT_FALSE(o.contains(QStringLiteral("externalMeta")));
  EXPECT_EQ(heap::state::taskFromJson(o), t);
}

TEST(RoundTrip, LiveSerializerOmitsDefaultSubKeysOfMeta) {
  Task t;
  t.id = QStringLiteral("GH-1");
  t.statusChangedAt = QDateTime(QDate(2026, 1, 1), QTime(1, 2, 3));
  t.externalMeta.author = QStringLiteral("grace");
  const QJsonObject meta = heap::state::taskToJson(t).value(QStringLiteral("externalMeta")).toObject();
  EXPECT_EQ(meta.keys(), QStringList{QStringLiteral("author")});
  EXPECT_EQ(heap::state::taskFromJson(heap::state::taskToJson(t)), t);
}

TEST(RoundTrip, SyncSerializerAlwaysEmitsEveryMetaKey) {
  // The merge transport reads a missing key as a deletion, so this serializer
  // may not skip defaults the way the live one does.
  Task t;
  t.id = QStringLiteral("LOCAL-1");
  const QJsonObject meta = heap::sync::SyncSerializer::taskToJson(t).value(QStringLiteral("externalMeta")).toObject();
  EXPECT_EQ(static_cast<std::size_t>(meta.keys().size()), heap::meta::fieldCount<ExternalMeta>())
      << "keys: " << meta.keys().join(QStringLiteral(",")).toStdString();
}

TEST(RoundTrip, MetaTimestampsAreNotNamedLikeHeapsOwnClock) {
  // JsonMerger reads a task's top-level `updatedAt` as heap's last-write clock
  // and applies "earlier wins" to any `createdAt` at any depth. A tracker
  // timestamp under either name would let a device that merely re-pulled
  // outrank one that actually edited.
  const QJsonObject o = heap::sync::SyncSerializer::taskToJson(makeFullTask());
  EXPECT_FALSE(o.contains(QStringLiteral("updatedAt")));
  EXPECT_FALSE(o.contains(QStringLiteral("createdAt")));
  const QJsonObject meta = o.value(QStringLiteral("externalMeta")).toObject();
  EXPECT_FALSE(meta.contains(QStringLiteral("updatedAt")));
  EXPECT_FALSE(meta.contains(QStringLiteral("createdAt")));
  EXPECT_TRUE(meta.contains(QStringLiteral("remoteUpdatedAt")));
  EXPECT_TRUE(meta.contains(QStringLiteral("remoteCreatedAt")));
}

TEST(RoundTrip, UnknownCommentCountSurvivesAsUnknown) {
  // -1 means "the provider did not say", which is not the same as zero
  // comments; a naive toInt() would read a missing key back as 0.
  Task t;
  t.id = QStringLiteral("GH-1");
  t.statusChangedAt = QDateTime(QDate(2026, 1, 1), QTime(1, 2, 3));
  t.externalMeta.project = QStringLiteral("acme/web");
  ASSERT_EQ(t.externalMeta.commentCount, -1);
  EXPECT_EQ(heap::state::taskFromJson(heap::state::taskToJson(t)).externalMeta.commentCount, -1);
  EXPECT_EQ(heap::sync::SyncSerializer::taskFromJson(heap::sync::SyncSerializer::taskToJson(t)).externalMeta.commentCount, -1);

  t.externalMeta.commentCount = 0;
  EXPECT_EQ(heap::state::taskFromJson(heap::state::taskToJson(t)).externalMeta.commentCount, 0);
  EXPECT_EQ(heap::sync::SyncSerializer::taskFromJson(heap::sync::SyncSerializer::taskToJson(t)).externalMeta.commentCount, 0);
}

TEST(RoundTrip, AV4FileWithoutMetaLoadsWithDefaults) {
  // Every state.json written before HEAP-117 has no externalMeta key at all.
  QJsonObject o;
  o["id"] = "GH-5";
  o["statusChangedAt"] = "2026-07-01T10:00:00";
  o["externalId"] = "5";
  o["externalProvider"] = "github";
  const Task t = heap::state::taskFromJson(o);
  EXPECT_EQ(t.externalMeta, ExternalMeta{});
  EXPECT_EQ(t.externalMeta.commentCount, -1);
  EXPECT_FALSE(t.externalMeta.crossProject);
}

// ── Property test ──

TEST(RoundTrip, ThousandRandomTasksSurviveBothSerializers) {
  Gen gen(104u);
  for(int i = 0; i < kCases; ++i) {
    const Task t = gen.task();
    const Task live = heap::state::taskFromJson(heap::state::taskToJson(t));
    ASSERT_EQ(live, t) << "live serializer, case " << i;
    const Task synced = heap::sync::SyncSerializer::taskFromJson(heap::sync::SyncSerializer::taskToJson(t));
    ASSERT_EQ(synced, t) << "sync serializer, case " << i;
  }
}

TEST(RoundTrip, ThousandRandomEventsSurviveBothSerializers) {
  Gen gen(20260709);
  for(int i = 0; i < kCases; ++i) {
    const CalEvent e = gen.event();
    ASSERT_EQ(heap::state::eventFromJson(heap::state::eventToJson(e)), e) << "live serializer, case " << i;
    ASSERT_EQ(heap::sync::SyncSerializer::eventFromJson(heap::sync::SyncSerializer::eventToJson(e)), e) << "sync serializer, case " << i;
  }
}

// ── Legacy read path ──

TEST(RoundTrip, LegacyBareDateDeadlineLandsAtMidnightWithoutTime) {
  QJsonObject o;
  o["id"] = "OLD-1";
  o["statusChangedAt"] = "2026-07-01T10:00:00";
  o["deadline"] = "2026-07-08";

  const Task live = heap::state::taskFromJson(o);
  EXPECT_EQ(live.scheduledAt, QDateTime(QDate(2026, 7, 8), QTime(0, 0)));
  EXPECT_EQ(live.dueAt, QDateTime(QDate(2026, 7, 8), QTime(0, 0)));
  EXPECT_FALSE(live.hasTime);

  const Task synced = heap::sync::SyncSerializer::taskFromJson(o);
  EXPECT_EQ(synced.scheduledAt, QDateTime(QDate(2026, 7, 8), QTime(0, 0)));
  EXPECT_FALSE(synced.hasTime);
}

TEST(RoundTrip, LegacyEmptyDeadlineStaysUnset) {
  QJsonObject o;
  o["id"] = "OLD-2";
  o["statusChangedAt"] = "2026-07-01T10:00:00";
  o["deadline"] = "";

  const Task live = heap::state::taskFromJson(o);
  EXPECT_FALSE(live.scheduledAt.isValid());
  EXPECT_FALSE(live.dueAt.isValid());
}

// Whole-second ISO datetimes written by pre-HEAP-131 builds still parse.
TEST(RoundTrip, DatetimesWrittenWithoutMillisecondsStillParse) {
  QJsonObject o;
  o["id"] = "OLD-3";
  o["statusChangedAt"] = "2026-07-01T10:00:00";
  o["timerStartedAt"] = "2026-07-01T11:30:00";

  const Task t = heap::state::taskFromJson(o);
  EXPECT_EQ(t.statusChangedAt, QDateTime(QDate(2026, 7, 1), QTime(10, 0)));
  EXPECT_EQ(t.timerStartedAt, QDateTime(QDate(2026, 7, 1), QTime(11, 30)));
}
