// A task's history (APP-165): what a change amounts to, the per-task cap,
// coalescing of streamed edits, and the state.json round-trip.

#include "history/TaskHistory.h"

#include <QJsonDocument>

#include <gtest/gtest.h>

using heap::history::diffTask;
using heap::history::HistoryEvent;
using heap::history::kMaxEventsPerTask;
using heap::history::TaskHistory;

namespace {

QDateTime fixedNow() {
  return {QDate(2026, 10, 6), QTime(12, 0)};
}

Task task() {
  Task t;
  t.id = QStringLiteral("LTE-1");
  t.title = QStringLiteral("Write it");
  t.status = QStringLiteral("todo");
  t.priority = QStringLiteral("P2");
  return t;
}

HistoryEvent ev(const QString& kind, const QString& from, const QString& to, const QDateTime& at, bool sync = false) {
  return HistoryEvent{.at = at, .kind = kind, .from = from, .to = to, .sync = sync};
}

}  // namespace

TEST(TaskHistoryDiff, CreatedThenEachField) {
  const Task a = task();
  const auto created = diffTask(nullptr, a, fixedNow(), false);
  ASSERT_EQ(created.size(), 1);
  EXPECT_EQ(created[0].kind, QStringLiteral("created"));
  EXPECT_EQ(created[0].to, QStringLiteral("todo"));

  Task b = a;
  b.status = QStringLiteral("prog");
  b.title = QStringLiteral("Write it well");
  b.priority = QStringLiteral("P0");
  b.dueAt = QDateTime(QDate(2026, 10, 9), QTime(0, 0));
  b.scheduledAt = QDateTime(QDate(2026, 10, 7), QTime(14, 30));
  b.scheduledHasTime = true;
  const auto d = diffTask(&a, b, fixedNow(), true);
  ASSERT_EQ(d.size(), 5);
  EXPECT_EQ(d[0].kind, QStringLiteral("status"));
  EXPECT_EQ(d[0].from, QStringLiteral("todo"));
  EXPECT_EQ(d[0].to, QStringLiteral("prog"));
  EXPECT_TRUE(d[0].sync);
  EXPECT_EQ(d[1].kind, QStringLiteral("title"));
  EXPECT_EQ(d[2].kind, QStringLiteral("priority"));
  EXPECT_EQ(d[3].kind, QStringLiteral("due"));
  EXPECT_EQ(d[3].to, QStringLiteral("2026-10-09"));
  EXPECT_EQ(d[4].kind, QStringLiteral("scheduled"));
  EXPECT_EQ(d[4].to, QStringLiteral("2026-10-07 14:30"));
}

TEST(TaskHistoryDiff, UntrackedFieldsSayNothing) {
  const Task a = task();
  Task b = a;
  b.desc = QStringLiteral("more words");
  b.rank = 42;
  EXPECT_TRUE(diffTask(&a, b, fixedNow(), false).isEmpty());
}

TEST(TaskHistoryLog, CapKeepsTheNewest) {
  TaskHistory h;
  for(int i = 0; i < kMaxEventsPerTask + 10; ++i) {
    h.append("p", "LTE-1", ev("status", QString::number(i), QString::number(i + 1), fixedNow().addSecs(i)));
  }
  const auto list = h.events("p", "LTE-1");
  ASSERT_EQ(list.size(), kMaxEventsPerTask);
  EXPECT_EQ(list.first().from, QString::number(10));
  EXPECT_EQ(list.last().to, QString::number(kMaxEventsPerTask + 10));
}

TEST(TaskHistoryLog, StreamedTitleEditsBecomeOne) {
  TaskHistory h;
  h.append("p", "LTE-1", ev("title", "a", "ab", fixedNow()));
  h.append("p", "LTE-1", ev("title", "ab", "abc", fixedNow().addSecs(5)));
  ASSERT_EQ(h.count("p", "LTE-1"), 1);
  EXPECT_EQ(h.events("p", "LTE-1")[0].from, QStringLiteral("a"));
  EXPECT_EQ(h.events("p", "LTE-1")[0].to, QStringLiteral("abc"));
  // Typed back to where it started: nothing happened.
  h.append("p", "LTE-1", ev("title", "abc", "a", fixedNow().addSecs(10)));
  EXPECT_EQ(h.count("p", "LTE-1"), 0);
  // Far apart, or from the other side, they stay separate.
  h.append("p", "LTE-1", ev("title", "a", "b", fixedNow()));
  h.append("p", "LTE-1", ev("title", "b", "c", fixedNow().addSecs(3600)));
  h.append("p", "LTE-1", ev("title", "c", "d", fixedNow().addSecs(3601), /*sync=*/true));
  EXPECT_EQ(h.count("p", "LTE-1"), 3);
}

TEST(TaskHistoryLog, StatusMovesAreNeverMerged) {
  TaskHistory h;
  h.append("p", "LTE-1", ev("status", "todo", "prog", fixedNow()));
  h.append("p", "LTE-1", ev("status", "prog", "review", fixedNow().addSecs(1)));
  EXPECT_EQ(h.count("p", "LTE-1"), 2);
}

TEST(TaskHistoryLog, ProfilesAreSeparate) {
  TaskHistory h;
  h.append("a", "LTE-1", ev("status", "todo", "prog", fixedNow()));
  EXPECT_EQ(h.count("b", "LTE-1"), 0);
}

TEST(TaskHistoryLog, JsonRoundTrip) {
  TaskHistory h;
  h.append("p1", "LTE-1", ev("created", "", "todo", fixedNow()));
  h.append("p1", "LTE-1", ev("status", "todo", "done", fixedNow().addSecs(60), true));
  h.append("p2", "github-7", ev("pushed", "", "done", fixedNow().addSecs(120), true));
  const QJsonObject json = h.toJson();
  // Survives the trip through bytes, as it does through state.json.
  const QJsonObject back = QJsonDocument::fromJson(QJsonDocument(json).toJson()).object();
  const TaskHistory r = TaskHistory::fromJson(back);
  EXPECT_EQ(r.events("p1", "LTE-1"), h.events("p1", "LTE-1"));
  EXPECT_EQ(r.events("p2", "github-7"), h.events("p2", "github-7"));
  // Compact: empty from/to and local source are not written.
  const QJsonObject first = json["p1"].toObject()["LTE-1"].toArray()[0].toObject();
  EXPECT_FALSE(first.contains("f"));
  EXPECT_FALSE(first.contains("s"));
}

TEST(TaskHistoryLog, JunkIsSkippedNotGuessed) {
  const QJsonObject o =
      QJsonDocument::fromJson(R"({"p":{"T":[{"k":"status"},{"t":"x","k":"y"},{"t":1700000000,"k":"status","v":"done"}],"U":"no"}})")
          .object();
  const TaskHistory h = TaskHistory::fromJson(o);
  ASSERT_EQ(h.count("p", "T"), 1);
  EXPECT_EQ(h.events("p", "T")[0].to, QStringLiteral("done"));
  EXPECT_EQ(h.count("p", "U"), 0);
}

TEST(TaskHistoryLog, VariantIsNewestFirst) {
  const QVariantList v =
      TaskHistory::toVariant({ev("created", "", "todo", fixedNow()), ev("status", "todo", "done", fixedNow().addSecs(1))});
  ASSERT_EQ(v.size(), 2);
  EXPECT_EQ(v[0].toMap().value("kind").toString(), QStringLiteral("status"));
}
