// The time machine (APP-162): retention of the hourly snapshots in history/,
// the snapshot file format, and restoring from one — whole, one profile as a
// copy, one task or note.
//
// Retention and the format are plain functions of their arguments, the clock
// included. The restore cases drive a real AppController against the
// QStandardPaths test-mode profile and judge what reached the models and disk.

#include "AppController.h"
#include "StateSerializer.h"

#include "storage/Snapshots.h"

#include <QApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

#include <iostream>

namespace hh = heap::history;

namespace {

// ── helpers ──

hh::SnapshotFile snap(const QDateTime& at, qint64 bytes = 1000, const QString& tag = QString()) {
  hh::SnapshotFile f;
  f.at = at;
  f.bytes = bytes;
  f.tag = tag;
  f.name = hh::fileNameFor(at, tag);
  return f;
}

QDateTime fixedNow() {
  return {QDate(2026, 10, 5), QTime(14, 30)};
}

QString appDataDir() {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QString historyDir() {
  return appDataDir() + QStringLiteral("/history");
}

void writeRaw(const QString& path, const QByteArray& bytes) {
  QDir().mkpath(QFileInfo(path).absolutePath());
  QFile f(path);
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write(bytes);
}

QJsonObject taskJson(const QString& id) {
  return QJsonObject{{"id", id},
                     {"title", id + QStringLiteral(" title")},
                     {"status", "todo"},
                     {"priority", "P2"},
                     {"statusChangedAt", QDateTime::currentDateTime().toString(Qt::ISODate)}};
}

QJsonArray defaultStatuses() {
  QJsonArray a;
  for(const char* id : {"backlog", "todo", "prog", "blocked", "review", "done"}) {
    a.append(QJsonObject{{"id", id}, {"name", id}, {"color", "#888888"}});
  }
  return a;
}

QJsonObject profileJson(const QString& id, const QJsonArray& tasks, const QJsonArray& notes = {}) {
  return QJsonObject{
      {"id", id}, {"name", id.toUpper()}, {"color", "#5cc2dd"}, {"tasks", tasks}, {"statuses", defaultStatuses()}, {"notes", notes}};
}

QByteArray stateDoc(const QJsonArray& profiles, const QString& active) {
  QJsonObject root;
  root["schemaVersion"] = heap::state::kSchemaVersion;
  root["activeProfileId"] = active;
  root["profiles"] = profiles;
  root["events"] = QJsonArray();
  root["settings"] = QJsonObject{{"welcomeSeen", true}};
  return QJsonDocument(root).toJson();
}

QStringList historyFiles() {
  return QDir(historyDir()).entryList({QStringLiteral("state-*.json.z")}, QDir::Files, QDir::Name);
}

}  // namespace

// ── File names ──

TEST(TimeMachineNames, RoundTripAndRejectJunk) {
  QDateTime at;
  QString tag;
  ASSERT_TRUE(hh::parseName(hh::fileNameFor(fixedNow()), &at, &tag));
  EXPECT_EQ(at, fixedNow());
  EXPECT_TRUE(tag.isEmpty());
  ASSERT_TRUE(hh::parseName(QStringLiteral("state-20261005-1430-pre-2.json.z"), &at, &tag));
  EXPECT_EQ(tag, QStringLiteral("pre"));
  EXPECT_FALSE(hh::parseName(QStringLiteral("state-20261005-143000.json")));  // a backups/ copy
  EXPECT_FALSE(hh::parseName(QStringLiteral("state-20261399-1430.json.z")));
  EXPECT_FALSE(hh::parseName(QStringLiteral("../state-20261005-1430.json.z")));
}

TEST(TimeMachinePolicy, DefaultsAndClamps) {
  const hh::Policy d = hh::policyFrom({});
  EXPECT_EQ(d.dailyDays, 30);
  EXPECT_EQ(d.maxBytes, 200LL * 1024 * 1024);
  const hh::Policy p = hh::policyFrom({{"historyDays", 90}, {"historyMaxMb", 500}});
  EXPECT_EQ(p.dailyDays, 90);
  EXPECT_EQ(p.maxBytes, 500LL * 1024 * 1024);
  EXPECT_EQ(hh::policyFrom({{"historyDays", 100000}}).dailyDays, 365);
  EXPECT_EQ(hh::policyFrom({{"historyDays", "junk"}}).dailyDays, 30);
}

// ── When a copy is due ──

TEST(TimeMachineDue, HourlyFromTheNewestUntaggedCopy) {
  EXPECT_TRUE(hh::isDue({}, fixedNow()));
  EXPECT_FALSE(hh::isDue({snap(fixedNow().addSecs(-30LL * 60))}, fixedNow()));
  EXPECT_TRUE(hh::isDue({snap(fixedNow().addSecs(-61LL * 60))}, fixedNow()));
  // A copy dated in the future (the clock went back) does not stop copies.
  EXPECT_TRUE(hh::isDue({snap(fixedNow().addDays(1))}, fixedNow()));
  // The copy taken before a restore is not the hourly one.
  EXPECT_TRUE(hh::isDue({snap(fixedNow().addSecs(-60), 1000, QStringLiteral("pre")), snap(fixedNow().addSecs(-2LL * 3600))}, fixedNow()));
}

// ── Retention ──

TEST(TimeMachineRetention, EveryHourOfTheLastTwoDaysIsKept) {
  QVector<hh::SnapshotFile> files;
  for(int h = 0; h < 47; ++h) {
    files.append(snap(fixedNow().addSecs(-3600LL * h)));
  }
  EXPECT_TRUE(hh::pickToDelete(files, fixedNow(), hh::Policy{}).isEmpty());
}

TEST(TimeMachineRetention, TwoAutomaticCopiesInOneHourKeepTheLater) {
  const QDateTime a(fixedNow().date(), QTime(10, 5));
  const QDateTime b(fixedNow().date(), QTime(10, 50));
  const QStringList gone = hh::pickToDelete({snap(a), snap(b), snap(fixedNow())}, fixedNow(), hh::Policy{});
  EXPECT_EQ(gone, QStringList{hh::fileNameFor(a)});
}

TEST(TimeMachineRetention, ACopyBeforeARestoreIsNotThinnedOutWithinTwoDays) {
  const QDateTime a(fixedNow().date(), QTime(10, 5));
  const QDateTime b(fixedNow().date(), QTime(10, 50));
  EXPECT_TRUE(hh::pickToDelete({snap(a, 1000, QStringLiteral("pre")), snap(b), snap(fixedNow())}, fixedNow(), hh::Policy{}).isEmpty());
}

TEST(TimeMachineRetention, OlderThanTwoDaysOnePerDayTheDaysLast) {
  const QDate day = fixedNow().date().addDays(-5);
  const QDateTime morning(day, QTime(9, 0));
  const QDateTime noon(day, QTime(12, 0));
  const QDateTime evening(day, QTime(22, 0));
  const QStringList gone = hh::pickToDelete({snap(fixedNow()), snap(morning), snap(noon), snap(evening)}, fixedNow(), hh::Policy{});
  EXPECT_EQ(gone.size(), 2);
  EXPECT_TRUE(gone.contains(hh::fileNameFor(morning)));
  EXPECT_TRUE(gone.contains(hh::fileNameFor(noon)));
}

TEST(TimeMachineRetention, PastTheDailyWindowEverythingGoesButTheNewest) {
  hh::Policy p;
  p.dailyDays = 7;
  const QDateTime old1 = fixedNow().addDays(-8);
  const QDateTime old2 = fixedNow().addDays(-40);
  const QDateTime kept = fixedNow().addDays(-6);
  QStringList gone = hh::pickToDelete({snap(fixedNow()), snap(kept), snap(old1), snap(old2)}, fixedNow(), p);
  gone.sort();
  QStringList want{hh::fileNameFor(old1), hh::fileNameFor(old2)};
  want.sort();
  EXPECT_EQ(gone, want);

  // The one copy there is stays, however old: it is all the history there is.
  EXPECT_TRUE(hh::pickToDelete({snap(old2)}, fixedNow(), p).isEmpty());
}

TEST(TimeMachineRetention, TheSizeCapTakesTheOldestFirstAndNeverTheNewest) {
  hh::Policy p;
  p.maxBytes = 2500;
  const QVector<hh::SnapshotFile> files{snap(fixedNow(), 1000),
                                        snap(fixedNow().addSecs(-3600), 1000),
                                        snap(fixedNow().addSecs(-7200), 1000),
                                        snap(fixedNow().addSecs(-3LL * 3600), 1000)};
  QStringList gone = hh::pickToDelete(files, fixedNow(), p);
  gone.sort();
  QStringList want{hh::fileNameFor(fixedNow().addSecs(-7200)), hh::fileNameFor(fixedNow().addSecs(-3LL * 3600))};
  want.sort();
  EXPECT_EQ(gone, want);

  p.maxBytes = 10;  // smaller than any one copy
  EXPECT_EQ(hh::pickToDelete(files, fixedNow(), p).size(), 3) << "the newest copy stays even over the cap";
}

// ── The file ──

TEST(TimeMachineFormat, EncodeDecodeRoundTrip) {
  const QByteArray state = stateDoc({profileJson("work", {taskJson("A-1"), taskJson("A-2")})}, "work");
  const QJsonObject summary = hh::summarize(QJsonDocument::fromJson(state).object());
  EXPECT_EQ(summary.value("tasks").toInt(), 2);
  EXPECT_EQ(summary.value("profiles").toInt(), 1);

  QByteArray back;
  QJsonObject sum;
  ASSERT_TRUE(hh::decode(hh::encode(state, summary), &back, &sum));
  EXPECT_EQ(back, state);
  EXPECT_EQ(sum, summary);
  EXPECT_FALSE(hh::decode(state, &back)) << "plain JSON is not a snapshot";
  EXPECT_FALSE(hh::decode(QByteArray("HEAPSNAP 1\n{}\nnot zlib"), &back));
}

TEST(TimeMachineFormat, WriteReadAndANameTakenTwice) {
  const QTemporaryDir dir;
  ASSERT_TRUE(dir.isValid());
  const QString d = dir.path() + QStringLiteral("/history");
  const QByteArray state = stateDoc({profileJson("work", {taskJson("A-1")})}, "work");
  const QJsonObject summary = hh::summarize(QJsonDocument::fromJson(state).object());
  const QString a = hh::write(d, state, summary, fixedNow(), QStringLiteral("pre"));
  const QString b = hh::write(d, state, summary, fixedNow(), QStringLiteral("pre"));
  EXPECT_EQ(a, QStringLiteral("state-20261005-1430-pre.json.z"));
  EXPECT_EQ(b, QStringLiteral("state-20261005-1430-pre-2.json.z"));
  EXPECT_EQ(hh::read(d + "/" + b), state);
  EXPECT_EQ(hh::readSummary(d + "/" + a).value("tasks").toInt(), 1);
  EXPECT_EQ(hh::list(d).size(), 2);
}

// 10k tasks: what one hourly copy costs the save worker.
TEST(TimeMachineFormat, TenThousandTasksEncodeCost) {
  QJsonArray tasks;
  for(int i = 0; i < 10000; ++i) {
    QJsonObject t = taskJson(QStringLiteral("BENCH-%1").arg(i));
    t["description"] = QStringLiteral("Some description text that a real task would carry, line %1").arg(i);
    tasks.append(t);
  }
  const QByteArray state = stateDoc({profileJson("work", tasks)}, "work");
  const QJsonObject summary = hh::summarize(QJsonDocument::fromJson(state).object());
  QElapsedTimer t;
  t.start();
  const QByteArray file = hh::encode(state, summary);
  const qint64 ms = t.elapsed();
  std::cout << "[time machine] 10k tasks: state " << state.size() / 1024 << " KB -> snapshot " << file.size() / 1024 << " KB in " << ms
            << " ms\n";
  EXPECT_LT(file.size(), state.size() / 3);
  EXPECT_LT(ms, 2000);
}

// ── Restoring, through AppController ──

class TimeMachine : public ::testing::Test {
 protected:
  void SetUp() override {
    QDir(appDataDir()).removeRecursively();
    QDir().mkpath(appDataDir());
  }
};

TEST_F(TimeMachine, ASaveTakesACopyOnceAnHour) {
  writeRaw(appDataDir() + "/state.json", stateDoc({profileJson("work", {taskJson("WORK-1")})}, "work"));
  AppController app;
  QVariantMap draft = app.newTaskDraft(QStringLiteral("todo"));
  draft["title"] = QStringLiteral("first");
  app.saveTask(draft);
  app.flushSave();
  ASSERT_EQ(historyFiles().size(), 1);
  EXPECT_EQ(app.listSnapshots().size(), 1);
  EXPECT_GE(app.listSnapshots().first().toMap().value("tasks").toInt(), 2);

  draft = app.newTaskDraft(QStringLiteral("todo"));
  draft["title"] = QStringLiteral("second");
  app.saveTask(draft);
  app.flushSave();
  EXPECT_EQ(historyFiles().size(), 1) << "not an hour yet";

  // The copy is two hours old now.
  const QString old = historyFiles().first();
  const QString aged = hh::fileNameFor(QDateTime::currentDateTime().addSecs(-2LL * 3600));
  ASSERT_TRUE(QFile::rename(historyDir() + "/" + old, historyDir() + "/" + aged));
  draft = app.newTaskDraft(QStringLiteral("todo"));
  draft["title"] = QStringLiteral("third");
  app.saveTask(draft);
  app.flushSave();
  EXPECT_EQ(historyFiles().size(), 2);
}

TEST_F(TimeMachine, ADeletedTaskComesBackAndUndoTakesItAgain) {
  writeRaw(appDataDir() + "/state.json", stateDoc({profileJson("work", {taskJson("WORK-1"), taskJson("WORK-2")})}, "work"));
  AppController app;
  const QString name = app.takeSnapshotNow(QString());
  ASSERT_FALSE(name.isEmpty());

  app.deleteTask(QStringLiteral("WORK-2"));
  ASSERT_LT(app.tasks()->indexOfId(QStringLiteral("WORK-2")), 0);

  const QVariantMap preview = app.previewSnapshot(name);
  ASSERT_TRUE(preview.value("ok").toBool()) << preview.value("error").toString().toStdString();
  const QVariantList missing = preview.value("missing").toList();
  ASSERT_EQ(missing.size(), 1);
  EXPECT_EQ(missing.first().toMap().value("id").toString(), QStringLiteral("WORK-2"));
  EXPECT_EQ(preview.value("totals").toMap().value("tasksRemoved").toInt(), 1);

  ASSERT_TRUE(app.restoreSnapshotItem(name, QStringLiteral("task"), QStringLiteral("work"), QStringLiteral("WORK-2")));
  EXPECT_GE(app.tasks()->indexOfId(QStringLiteral("WORK-2")), 0);
  EXPECT_TRUE(app.previewSnapshot(name).value("missing").toList().isEmpty());

  app.undo();
  EXPECT_LT(app.tasks()->indexOfId(QStringLiteral("WORK-2")), 0) << "restoring one item is undoable";
}

TEST_F(TimeMachine, AnEditedTaskGoesBackToTheSnapshotVersion) {
  writeRaw(appDataDir() + "/state.json", stateDoc({profileJson("work", {taskJson("WORK-1")})}, "work"));
  AppController app;
  const QString name = app.takeSnapshotNow(QString());
  QVariantMap t = app.taskById(QStringLiteral("WORK-1"));
  t["title"] = QStringLiteral("renamed");
  app.saveTask(t);
  ASSERT_EQ(app.taskById(QStringLiteral("WORK-1")).value("title").toString(), QStringLiteral("renamed"));

  const QVariantList changed = app.previewSnapshot(name).value("changed").toList();
  ASSERT_EQ(changed.size(), 1);
  ASSERT_TRUE(app.restoreSnapshotItem(name, QStringLiteral("task"), QStringLiteral("work"), QStringLiteral("WORK-1")));
  EXPECT_EQ(app.taskById(QStringLiteral("WORK-1")).value("title").toString(), QStringLiteral("WORK-1 title"));
}

TEST_F(TimeMachine, ARankTheLoadSpreadIsNotAChange) {
  // No ranks in the file: loading spreads the ties, so the live tasks carry
  // ranks the snapshot does not. That is not an edit to offer to roll back.
  const QByteArray doc = stateDoc({profileJson("work", {taskJson("WORK-1"), taskJson("WORK-2")})}, "work");
  writeRaw(appDataDir() + "/state.json", doc);
  const QString name =
      hh::write(historyDir(), doc, hh::summarize(QJsonDocument::fromJson(doc).object()), QDateTime::currentDateTime().addSecs(-2LL * 3600));
  ASSERT_FALSE(name.isEmpty());
  AppController app;
  const QVariantMap preview = app.previewSnapshot(name);
  ASSERT_TRUE(preview.value("ok").toBool());
  EXPECT_TRUE(preview.value("changed").toList().isEmpty());
  EXPECT_TRUE(preview.value("missing").toList().isEmpty());
}

TEST_F(TimeMachine, ADeletedNoteComesBack) {
  const QJsonArray notes{QJsonObject{{"id", "n-1"}, {"title", "Plan"}, {"body", "# Plan\n\nkeep this"}},
                         QJsonObject{{"id", "n-2"}, {"title", "Other"}, {"body", "# Other"}}};
  writeRaw(appDataDir() + "/state.json", stateDoc({profileJson("work", {taskJson("WORK-1")}, notes)}, "work"));
  AppController app;
  const QString name = app.takeSnapshotNow(QString());
  app.deleteNote(QStringLiteral("n-1"));
  ASSERT_TRUE(app.noteBody(QStringLiteral("n-1")).isEmpty());
  ASSERT_TRUE(app.restoreSnapshotItem(name, QStringLiteral("note"), QStringLiteral("work"), QStringLiteral("n-1")));
  EXPECT_EQ(app.noteBody(QStringLiteral("n-1")), QStringLiteral("# Plan\n\nkeep this"));
}

TEST_F(TimeMachine, AProfileComesBackAsACopyBesideTheLiveOne) {
  writeRaw(appDataDir() + "/state.json",
           stateDoc({profileJson("work", {taskJson("WORK-1"), taskJson("WORK-2")}), profileJson("home", {taskJson("HOME-1")})}, "work"));
  AppController app;
  const QString name = app.takeSnapshotNow(QString());
  app.deleteTask(QStringLiteral("WORK-1"));

  const QString id = app.restoreSnapshotProfile(name, QStringLiteral("work"));
  ASSERT_FALSE(id.isEmpty());
  EXPECT_NE(id, QStringLiteral("work"));
  const QVariantMap copy = app.profileById(id);
  const QString copyName = copy.value("name").toString();
  EXPECT_TRUE(copyName.startsWith(QStringLiteral("WORK ("))) << copyName.toStdString();
  EXPECT_EQ(app.profiles().size(), 3);
  EXPECT_EQ(app.activeProfileId(), QStringLiteral("work")) << "the live profile stays in front";

  // Its tasks are new tasks: WORK-2 is still live, so the copy's gets a fresh id.
  app.setActiveProfileId(id);
  EXPECT_EQ(app.tasks()->rowCount(), 2);
  EXPECT_GE(app.tasks()->indexOfId(QStringLiteral("WORK-1")), 0) << "an id nobody holds any more is kept";
  EXPECT_LT(app.tasks()->indexOfId(QStringLiteral("WORK-2")), 0) << "an id the live profile holds is reissued";
}

TEST_F(TimeMachine, RestoringEverythingIsItselfRestorable) {
  writeRaw(appDataDir() + "/state.json", stateDoc({profileJson("work", {taskJson("WORK-1")})}, "work"));
  AppController app;
  const QString name = app.takeSnapshotNow(QString());
  QVariantMap draft = app.newTaskDraft(QStringLiteral("todo"));
  draft["title"] = QStringLiteral("made after the snapshot");
  const QString added = draft.value("id").toString();
  ASSERT_TRUE(app.saveTask(draft));
  ASSERT_GE(app.tasks()->indexOfId(added), 0);

  ASSERT_TRUE(app.restoreSnapshot(name));
  EXPECT_LT(app.tasks()->indexOfId(added), 0);

  QString pre;
  for(const QVariant& v : app.listSnapshots()) {
    if(v.toMap().value("tag").toString() == QLatin1String("pre")) {
      pre = v.toMap().value("name").toString();
    }
  }
  ASSERT_FALSE(pre.isEmpty()) << "the replaced state is in history";
  ASSERT_TRUE(app.restoreSnapshot(pre));
  EXPECT_GE(app.tasks()->indexOfId(added), 0);
}

TEST_F(TimeMachine, ANameWithAPathIsRefused) {
  AppController app;
  const QVariantMap preview = app.previewSnapshot(QStringLiteral("../state.json"));
  EXPECT_FALSE(preview.value("ok").toBool());
  EXPECT_FALSE(app.restoreSnapshot(QStringLiteral("..\\state-20261005-1430.json.z")));
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  const QApplication qapp(argc, argv);

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
