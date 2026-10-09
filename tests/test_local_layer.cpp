// The task's local layer (ADR 0001, APP-244): one invariant, run over every
// path that writes tracker data into a card — `local` before == `local` after.
// Features that add fields to TaskLocal (APP-236…241) extend makeLocal()
// below rather than writing their own matrix. Tracker traffic never leaves the
// process: pulls go straight through mergeExternalTasks.

#include "AppController.h"
#include "Models.h"
#include "StateSerializer.h"

#include "integrations/IntegrationTypes.h"
#include "local/Effective.h"
#include "sync/JsonMerger.h"
#include "sync/SyncSerializer.h"

#include <QApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

#include <gtest/gtest.h>

#include <functional>
#include <memory>

namespace locallayer {

using heap::integrations::ExternalTask;

// Every field of TaskLocal set to something that is not its default.
TaskLocal makeLocal() {
  TaskLocal l;
  l.notes = QStringLiteral("tried: smaller pool\n- did not help");
  l.checklist = {LocalCheckItem{QStringLiteral("c1"), QStringLiteral("repro"), 1, true, false, QString()},
                 LocalCheckItem{QStringLiteral("c2"), QStringLiteral("deep step"), 3, false, false, QString()}};
  l.myPriority = QStringLiteral("P0");
  l.myDueAt = QDateTime(QDate(2026, 10, 15), QTime(12, 0));
  l.myDueHasTime = true;
  l.myPriorityBase = QStringLiteral("P2");
  l.myDueBase = QDateTime(QDate(2026, 10, 20), QTime(0, 0));
  l.tags = {LocalTag{QStringLiteral("after-release"), QStringLiteral("#b1a7f0")}};
  l.related = {LocalLink{
      QStringLiteral("r1"), QStringLiteral("related"), QStringLiteral("https://gitlab.example/a/-/merge_requests/17"), QString()}};
  l.commentDraft = QStringLiteral("Reproduced, see notes.");
  l.doneFrom = QStringLiteral("review");
  l.sessions = {TimerSession{QStringLiteral("before-0.8.0"), QDateTime(), QDateTime(), 1200},
                TimerSession{QStringLiteral("s1"), QDateTime(QDate(2026, 10, 8), QTime(9, 0)), QDateTime(QDate(2026, 10, 8), QTime(10, 30)), 0}};
  l.extra = QJsonObject{{QStringLiteral("futureLocalField"), 1}};
  return l;
}

class LocalLayer : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<::AppController>();
    app_->tasks()->reset({});
    app_->setLanguage(QStringLiteral("en"));
    app_->setAppSettingsJson(QStringLiteral("{}"));
    writeConfig(QJsonObject{{QStringLiteral("repo"), QStringLiteral("acme/app")}});
  }

  void TearDown() override {
    app_->setAppSettingsJson(QStringLiteral("{}"));
    app_.reset();
  }

  void writeConfig(const QJsonObject& cfg) {
    QJsonObject settings = QJsonDocument::fromJson(app_->appSettingsJson().toUtf8()).object();
    QJsonObject integrations = settings.value(QStringLiteral("integrations")).toObject();
    integrations.insert(QStringLiteral("github"), cfg);
    settings.insert(QStringLiteral("integrations"), integrations);
    app_->setAppSettingsJson(QString::fromUtf8(QJsonDocument(settings).toJson(QJsonDocument::Compact)));
  }

  static ExternalTask issue(const QString& number, const QString& title = QStringLiteral("title")) {
    ExternalTask e;
    e.providerId = QStringLiteral("github");
    e.externalId = number;
    e.url = QStringLiteral("https://github.com/acme/app/issues/") + number;
    e.title = title;
    e.body = QStringLiteral("body");
    e.status = QStringLiteral("open");
    e.project = QStringLiteral("acme/app");
    return e;
  }

  void merge(const QVector<ExternalTask>& issues, bool complete = true) {
    app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("gh-"), issues, complete);
  }

  const Task* task(const QString& id) const {
    const int row = app_->tasks()->indexOfId(id);
    return row >= 0 ? &app_->tasks()->items().at(row) : nullptr;
  }

  // A pulled card #1 that already holds every local field.
  void pullCardWithLocal() {
    merge({issue("1")});
    ASSERT_NE(task("gh-1"), nullptr);
    Task t = *task("gh-1");
    t.local = makeLocal();
    app_->tasks()->upsert(t);
  }

  std::unique_ptr<::AppController> app_;
};

// One row per sync path. Each takes the card through that path and the test
// checks `local` afterwards.
struct SyncPath {
  const char* name;
  std::function<void(LocalLayer&)> run;
};

}  // namespace locallayer

using heap::integrations::ExternalTask;
using locallayer::LocalLayer;

// ── The invariant, path by path ──

TEST_F(LocalLayer, APullThatChangesEveryTrackerFieldLeavesLocalAlone) {
  pullCardWithLocal();
  ExternalTask e = issue("1", QStringLiteral("renamed upstream"));
  e.body = QStringLiteral("rewritten upstream");
  e.status = QStringLiteral("closed");
  e.priority = QStringLiteral("P1");
  e.labels = {QStringLiteral("bug")};
  e.dueAt = QDateTime(QDate(2026, 11, 1), QTime(0, 0));
  merge({e});
  EXPECT_EQ(task("gh-1")->local, locallayer::makeLocal());
  EXPECT_EQ(task("gh-1")->title, QString("renamed upstream")) << "the tracker fields still follow the tracker";
}

TEST_F(LocalLayer, GoneUpstreamLeavesLocalAlone) {
  pullCardWithLocal();
  merge({issue("2")});  // complete, same filter, #1 missing
  ASSERT_TRUE(task("gh-1")->externalMeta.goneUpstream || task("gh-1")->externalMeta.outOfScope);
  EXPECT_EQ(task("gh-1")->local, locallayer::makeLocal());
}

TEST_F(LocalLayer, OutOfScopeLeavesLocalAlone) {
  pullCardWithLocal();
  writeConfig(QJsonObject{{QStringLiteral("repo"), QString()}});  // a different filter
  merge({issue("2")});
  ASSERT_TRUE(task("gh-1")->externalMeta.outOfScope);
  EXPECT_EQ(task("gh-1")->local, locallayer::makeLocal());
}

TEST_F(LocalLayer, ReconnectingTheIntegrationLeavesLocalAlone) {
  pullCardWithLocal();
  app_->disconnectIntegration(QStringLiteral("github"));
  writeConfig(QJsonObject{{QStringLiteral("repo"), QStringLiteral("acme/app")}});
  merge({issue("1", QStringLiteral("after reconnect"))});
  ASSERT_NE(task("gh-1"), nullptr);
  EXPECT_EQ(task("gh-1")->local, locallayer::makeLocal());
}

TEST_F(LocalLayer, TakingTheTrackersSideOfAConflictLeavesLocalAlone) {
  pullCardWithLocal();
  Task t = *task("gh-1");
  t.priority = QStringLiteral("P3");
  t.externalMeta.priority = QStringLiteral("P1");
  t.externalMeta.conflicts = {QStringLiteral("priority"), QStringLiteral("status")};
  app_->tasks()->upsert(t);
  app_->resolveTrackerConflict(QStringLiteral("gh-1"), /*useTracker=*/true);
  EXPECT_EQ(task("gh-1")->local, locallayer::makeLocal());
}

TEST_F(LocalLayer, TakingTheTrackersTextOnlyAddsToTheNotepad) {
  pullCardWithLocal();
  Task t = *task("gh-1");
  t.desc = QStringLiteral("my local description");
  t.externalMeta.conflicts = {QStringLiteral("body")};
  app_->tasks()->upsert(t);
  app_->resolveTrackerConflict(QStringLiteral("gh-1"), /*useTracker=*/true);
  TaskLocal expected = locallayer::makeLocal();
  const TaskLocal& got = task("gh-1")->local;
  EXPECT_TRUE(got.notes.startsWith(expected.notes)) << "what was there is kept";
  EXPECT_TRUE(got.notes.contains(QStringLiteral("my local description")));
  expected.notes = got.notes;
  EXPECT_EQ(got, expected) << "nothing but the notepad changes";
}

TEST_F(LocalLayer, ImportingAnExportedProfileKeepsLocal) {
  pullCardWithLocal();
  const QString json = app_->exportActiveProfileJson();
  const QString error = app_->importProfileFromJson(json, /*activate=*/true);
  ASSERT_TRUE(error.isEmpty()) << error.toStdString();
  bool found = false;
  for(const Task& t : app_->tasks()->items()) {
    if(t.externalId == QStringLiteral("1")) {
      EXPECT_EQ(t.local, locallayer::makeLocal());
      found = true;
    }
  }
  EXPECT_TRUE(found);
}

TEST_F(LocalLayer, SavingAndLoadingKeepsLocal) {
  Task t;
  t.id = QStringLiteral("T-1");
  t.statusChangedAt = QDateTime(QDate(2026, 1, 1), QTime(0, 0));
  t.local = locallayer::makeLocal();
  EXPECT_EQ(heap::state::taskFromJson(heap::state::taskToJson(t)).local, t.local);
  EXPECT_EQ(heap::sync::SyncSerializer::taskFromJson(heap::sync::SyncSerializer::taskToJson(t)).local, t.local);
}

// Two devices: one edits my notes and ticks a checklist item, the other got a
// pull that changed the tracker's title. Both land; neither touches the other.
TEST_F(LocalLayer, JsonMergerMergesLocalPerElementBesideTrackerFields) {
  Task base;
  base.id = QStringLiteral("gh-1");
  base.title = QStringLiteral("title");
  base.statusChangedAt = QDateTime(QDate(2026, 1, 1), QTime(0, 0));
  base.local = locallayer::makeLocal();

  Task mine = base;
  mine.local.notes += QStringLiteral("\nmore");
  mine.local.checklist[1].done = true;
  Task theirs = base;
  theirs.title = QStringLiteral("renamed upstream");
  theirs.local.checklist.append(LocalCheckItem{QStringLiteral("c3"), QStringLiteral("added on laptop"), 1, false, false, QString()});

  const auto wrap = [](const Task& t) {
    return QJsonObject{{QStringLiteral("tasks"), QJsonArray{heap::sync::SyncSerializer::taskToJson(t)}}};
  };
  const heap::sync::MergeResult r = heap::sync::JsonMerger::merge(wrap(base), wrap(mine), wrap(theirs));
  for(const auto& c : r.conflicts) {
    ADD_FAILURE() << "conflict at " << c.path.toStdString();
  }
  ASSERT_TRUE(r.ok);
  const Task merged = heap::sync::SyncSerializer::taskFromJson(r.merged["tasks"].toArray().at(0).toObject());
  EXPECT_EQ(merged.title, QString("renamed upstream"));
  EXPECT_EQ(merged.local.notes, mine.local.notes);
  ASSERT_EQ(merged.local.checklist.size(), 3);
  EXPECT_TRUE(merged.local.checklist[1].done);
}

// ── Effective values ──

TEST(LocalEffective, MineWinsOverTheTrackersAndFallsBackToIt) {
  Task t;
  t.priority = QStringLiteral("P2");
  t.dueAt = QDateTime(QDate(2026, 10, 20), QTime(0, 0));
  EXPECT_EQ(heap::local::effectivePriority(t), QString("P2"));
  EXPECT_EQ(heap::local::effectiveDueAt(t), t.dueAt);
  EXPECT_FALSE(heap::local::effectiveDueHasTime(t));
  t.local.myPriority = QStringLiteral("P0");
  t.local.myDueAt = QDateTime(QDate(2026, 10, 15), QTime(12, 0));
  t.local.myDueHasTime = true;
  EXPECT_EQ(heap::local::effectivePriority(t), QString("P0"));
  EXPECT_EQ(heap::local::effectiveDueAt(t), t.local.myDueAt);
  EXPECT_TRUE(heap::local::effectiveDueHasTime(t));
}

TEST(LocalJson, AnEmptyLayerIsOmittedFromStateJson) {
  Task t;
  t.id = QStringLiteral("T-1");
  t.statusChangedAt = QDateTime(QDate(2026, 1, 1), QTime(0, 0));
  EXPECT_FALSE(heap::state::taskToJson(t).contains(QStringLiteral("local")));
  EXPECT_TRUE(heap::sync::SyncSerializer::taskToJson(t).contains(QStringLiteral("local"))) << "the merge form writes every key";
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QApplication qapp(argc, argv);
  const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  if(!appData.isEmpty()) {
    QFile::remove(appData + QStringLiteral("/state.json"));
  }
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
