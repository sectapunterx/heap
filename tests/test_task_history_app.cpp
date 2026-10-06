// Task history through a real AppController (APP-165): the central mutation
// paths record, a tracker pull marks its own, loads do not, and the log
// survives a save and a fresh start.

#include "AppController.h"
#include "Models.h"

#include "integrations/IntegrationTypes.h"

#include <QApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

QString statePath() {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/state.json");
}

QVariantList kinds(const QVariantList& events) {
  QVariantList out;
  for(const QVariant& v : events) {
    out.append(v.toMap().value(QStringLiteral("kind")));
  }
  return out;
}

class TaskHistoryApp : public ::testing::Test {
 protected:
  void SetUp() override {
    QFile::remove(statePath());
  }

  void TearDown() override {
    QFile::remove(statePath());
  }

  static QString addTask(AppController& app, const QString& title) {
    QVariantMap draft = app.newTaskDraft(QStringLiteral("todo"));
    draft[QStringLiteral("title")] = title;
    EXPECT_TRUE(app.saveTask(draft));
    return draft.value(QStringLiteral("id")).toString();
  }
};

TEST_F(TaskHistoryApp, CreateMoveRetitleAreRecordedNewestFirst) {
  AppController app;
  const QString id = addTask(app, QStringLiteral("write it"));
  ASSERT_FALSE(id.isEmpty());
  app.moveTask(id, QStringLiteral("prog"));
  QVariantMap edit = app.taskById(id);
  edit[QStringLiteral("title")] = QStringLiteral("write it well");
  ASSERT_TRUE(app.saveTask(edit));

  const QVariantList h = app.taskHistory(id);
  ASSERT_GE(h.size(), 3);
  EXPECT_EQ(h.first().toMap().value(QStringLiteral("kind")).toString(), QStringLiteral("title"));
  EXPECT_EQ(h.last().toMap().value(QStringLiteral("kind")).toString(), QStringLiteral("created"));
  bool sawMove = false;
  for(const QVariant& v : h) {
    const QVariantMap e = v.toMap();
    if(e.value(QStringLiteral("kind")).toString() == QStringLiteral("status")) {
      sawMove = true;
      EXPECT_EQ(e.value(QStringLiteral("from")).toString(), QStringLiteral("todo"));
      EXPECT_EQ(e.value(QStringLiteral("to")).toString(), QStringLiteral("prog"));
      EXPECT_FALSE(e.value(QStringLiteral("sync")).toBool());
    }
  }
  EXPECT_TRUE(sawMove) << "a move between columns left no trace";
}

TEST_F(TaskHistoryApp, TrackerPullIsMarkedAsComingFromTheTracker) {
  AppController app;
  app.tasks()->reset({});
  heap::integrations::ExternalTask e;
  e.providerId = QStringLiteral("github");
  e.externalId = QStringLiteral("5");
  e.url = QStringLiteral("https://github.com/acme/app/issues/5");
  e.title = QStringLiteral("from upstream");
  e.status = QStringLiteral("open");
  app.mergeExternalTasks(QStringLiteral("github"), QStringLiteral("gh-"), {e});
  e.status = QStringLiteral("closed");
  app.mergeExternalTasks(QStringLiteral("github"), QStringLiteral("gh-"), {e});

  const QVariantList h = app.taskHistory(QStringLiteral("gh-5"));
  ASSERT_EQ(h.size(), 2);
  const QVariantMap moved = h.first().toMap();
  EXPECT_EQ(moved.value(QStringLiteral("kind")).toString(), QStringLiteral("status"));
  EXPECT_EQ(moved.value(QStringLiteral("to")).toString(), QStringLiteral("done"));
  EXPECT_TRUE(moved.value(QStringLiteral("sync")).toBool());
  EXPECT_TRUE(h.last().toMap().value(QStringLiteral("sync")).toBool()) << "a pulled issue is not one the user created";
}

TEST_F(TaskHistoryApp, SurvivesASaveAndAFreshStartAndALoadAddsNothing) {
  QString id;
  QVariantList before;
  {
    AppController app;
    id = addTask(app, QStringLiteral("persist me"));
    app.moveTask(id, QStringLiteral("done"));
    before = app.taskHistory(id);
    ASSERT_FALSE(before.isEmpty());
    app.flushSave();
  }
  // On disk as one root key, not inside the task (no schema change).
  QFile f(statePath());
  ASSERT_TRUE(f.open(QIODevice::ReadOnly));
  const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
  EXPECT_TRUE(root.contains(QStringLiteral("taskHistory")));
  const AppController again;
  EXPECT_EQ(kinds(again.taskHistory(id)), kinds(before)) << "the log changed across a restart";
}

TEST_F(TaskHistoryApp, UndoingADeleteIsNotACreation) {
  AppController app;
  const QString id = addTask(app, QStringLiteral("delete me"));
  const int n = static_cast<int>(app.taskHistory(id).size());
  app.deleteTask(id);
  app.undo();
  EXPECT_EQ(app.taskHistory(id).size(), n);
}

}  // namespace

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
