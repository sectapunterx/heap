// What a sync shows (APP-180, APP-186, APP-187): new cards named and marked,
// `is:new`, the "a sync is out" flag, and the event log. Tracker traffic goes
// to a local FakeHttpServer, never a live API.

#include "AppController.h"
#include "FakeHttpServer.h"
#include "Models.h"

#include "integrations/IntegrationTypes.h"
#include "notify/EventLog.h"

#include <QApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

#include <memory>

namespace syncvis {

using heap::integrations::ExternalTask;

// ── The ring buffer itself ──

TEST(EventLog, KeepsTheNewestHundred) {
  heap::notify::EventLog log;
  const QDateTime t0(QDate(2026, 10, 6), QTime(9, 0));
  for(int i = 0; i < 130; ++i) {
    log.add(t0.addSecs(i), QStringLiteral("error"), QStringLiteral("failure %1").arg(i));
  }
  EXPECT_EQ(log.size(), heap::notify::EventLog::kCapacity);
  EXPECT_EQ(log.entries().front().message, QStringLiteral("failure 30")) << "the oldest are the ones dropped";
  const QVariantList list = log.toVariantList();
  ASSERT_EQ(list.size(), 100);
  EXPECT_EQ(list.first().toMap().value(QStringLiteral("message")).toString(), QStringLiteral("failure 129")) << "newest first";
}

TEST(EventLog, TheSameThingSaidAgainIsCounted) {
  heap::notify::EventLog log;
  const QDateTime t0(QDate(2026, 10, 6), QTime(9, 0));
  log.add(t0, QStringLiteral("error"), QStringLiteral("Jira sync failed"));
  log.add(t0.addSecs(60), QStringLiteral("error"), QStringLiteral("Jira sync failed"));
  ASSERT_EQ(log.size(), 1);
  EXPECT_EQ(log.entries().back().count, 2);
  EXPECT_EQ(log.entries().back().at, t0.addSecs(60));
  // Not in a row: a new entry.
  log.add(t0.addSecs(70), QStringLiteral("undo"), QStringLiteral("Deleted: A-1"));
  log.add(t0.addSecs(80), QStringLiteral("error"), QStringLiteral("Jira sync failed"));
  EXPECT_EQ(log.size(), 3);
  // Same words about other tasks: also new.
  log.add(t0.addSecs(90), QStringLiteral("error"), QStringLiteral("Jira sync failed"), {QStringLiteral("x")});
  EXPECT_EQ(log.size(), 4);
}

// ── Through the controller ──

class SyncVisibility : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<::AppController>();
    app_->tasks()->reset({});
    app_->setLanguage(QStringLiteral("en"));
    app_->setAppSettingsJson(QStringLiteral("{}"));
  }

  void TearDown() override {
    app_->setAppSettingsJson(QStringLiteral("{}"));
    app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QString());
    app_.reset();
  }

  static ExternalTask issue(const QString& number, const QString& title = QString()) {
    ExternalTask e;
    e.providerId = QStringLiteral("github");
    e.externalId = number;
    e.url = QStringLiteral("https://github.com/acme/app/issues/") + number;
    e.title = title.isEmpty() ? QStringLiteral("title ") + number : title;
    e.status = QStringLiteral("open");
    e.project = QStringLiteral("acme/app");
    return e;
  }

  ::AppController::MergeStats merge(const QVector<ExternalTask>& issues) {
    return app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("gh-"), issues, false);
  }

  std::unique_ptr<::AppController> app_;
};

TEST_F(SyncVisibility, NewCardsOfALaterSyncAreUnseen_TheFirstImportIsNot) {
  const auto first = merge({issue("1"), issue("2")});
  EXPECT_EQ(first.addedIds, (QStringList{QStringLiteral("gh-1"), QStringLiteral("gh-2")}));
  EXPECT_FALSE(app_->isTaskUnseen(QStringLiteral("gh-1"))) << "the first import filled the board with dots";

  QSignalSpy unseen(app_.get(), &AppController::unseenTasksChanged);
  const auto second = merge({issue("1"), issue("2"), issue("3")});
  EXPECT_EQ(second.addedIds, QStringList{QStringLiteral("gh-3")});
  EXPECT_TRUE(app_->isTaskUnseen(QStringLiteral("gh-3")));
  EXPECT_FALSE(app_->isTaskUnseen(QStringLiteral("gh-1"))) << "an existing card is not new";
  EXPECT_EQ(unseen.count(), 1);

  const int rev = app_->unseenRevision();
  app_->markTaskSeen(QStringLiteral("gh-3"));
  EXPECT_FALSE(app_->isTaskUnseen(QStringLiteral("gh-3")));
  EXPECT_GT(app_->unseenRevision(), rev);
  // Seeing it twice changes nothing.
  app_->markTaskSeen(QStringLiteral("gh-3"));
  EXPECT_EQ(unseen.count(), 2);
}

TEST_F(SyncVisibility, IsNewFiltersToTheLatestSyncsCards) {
  merge({issue("1")});
  app_->syncProvider(QStringLiteral("nobody"));  // starts a run, finds no tracker
  merge({issue("1"), issue("2"), issue("3")});
  EXPECT_EQ(app_->syncNewTaskIds(), (QStringList{QStringLiteral("gh-2"), QStringLiteral("gh-3")}));
  QStringList ids = app_->compileSearch(QStringLiteral("is:new")).value(QStringLiteral("ids")).toStringList();
  ids.sort();
  EXPECT_EQ(ids, (QStringList{QStringLiteral("gh-2"), QStringLiteral("gh-3")}));
  EXPECT_TRUE(app_->searchProblems(QStringLiteral("is:new")).isEmpty());

  // Seeing a card does not take it out of the filter under the user's eyes.
  app_->markTaskSeen(QStringLiteral("gh-2"));
  EXPECT_EQ(app_->compileSearch(QStringLiteral("is:new")).value(QStringLiteral("ids")).toStringList().size(), 2);
}

TEST_F(SyncVisibility, TheToastNamesThreeNewTicketsAndCountsTheRest) {
  merge({issue("1")});
  QVector<ExternalTask> batch{issue("1")};
  for(int i = 2; i <= 6; ++i) {
    batch.append(issue(QString::number(i), QStringLiteral("Ticket number %1").arg(i)));
  }
  batch[0].title = QStringLiteral("renamed");
  const auto stats = merge(batch);
  ASSERT_EQ(stats.added, 5);

  QSignalSpy news(app_.get(), &AppController::syncNews);
  QSignalSpy toasts(app_.get(), &AppController::toast);
  app_->reportSync(QStringLiteral("GitHub"), stats, false);
  ASSERT_EQ(news.count(), 1);
  EXPECT_EQ(toasts.count(), 0) << "one message per sync, not a toast and a news line";
  const QString msg = news.at(0).at(0).toString();
  EXPECT_EQ(msg, QStringLiteral("GitHub: 5 new — #2 Ticket number 2, #3 Ticket number 3, #4 Ticket number 4, 2 more · 1 updated"))
      << msg.toStdString();
  EXPECT_EQ(news.at(0).at(1).toStringList().size(), 5);

  const QVariantList log = app_->eventLog();
  ASSERT_FALSE(log.isEmpty());
  const QVariantMap entry = log.first().toMap();
  EXPECT_EQ(entry.value(QStringLiteral("kind")).toString(), QStringLiteral("sync"));
  EXPECT_EQ(entry.value(QStringLiteral("message")).toString(), msg);
  EXPECT_EQ(entry.value(QStringLiteral("taskIds")).toStringList().size(), 5);
}

TEST_F(SyncVisibility, ALongTitleIsCutAndRussianSaysEshche) {
  merge({issue("1")});
  app_->setLanguage(QStringLiteral("ru"));
  QVector<ExternalTask> batch{issue("1")};
  batch.append(issue(QStringLiteral("2"), QString(60, QChar('x'))));
  for(int i = 3; i <= 5; ++i) {
    batch.append(issue(QString::number(i)));
  }
  const auto stats = merge(batch);
  QSignalSpy news(app_.get(), &AppController::syncNews);
  app_->reportSync(QStringLiteral("GitHub"), stats, false);
  ASSERT_EQ(news.count(), 1);
  const QString msg = news.at(0).at(0).toString();
  EXPECT_TRUE(msg.contains(QStringLiteral("#2 ") + QString(39, QChar('x')) + QChar(0x2026))) << msg.toStdString();
  EXPECT_TRUE(msg.contains(QStringLiteral("ещё 1"))) << msg.toStdString();
}

TEST_F(SyncVisibility, NothingNewIsAPlainToast) {
  merge({issue("1")});
  auto batch = QVector<ExternalTask>{issue("1")};
  batch[0].title = QStringLiteral("renamed");
  const auto stats = merge(batch);
  QSignalSpy news(app_.get(), &AppController::syncNews);
  QSignalSpy toasts(app_.get(), &AppController::toast);
  app_->reportSync(QStringLiteral("GitHub"), stats, false);
  EXPECT_EQ(news.count(), 0);
  ASSERT_EQ(toasts.count(), 1);
  EXPECT_EQ(toasts.at(0).at(0).toString(), QStringLiteral("GitHub: 0 new · 1 updated"));
}

TEST_F(SyncVisibility, ErrorsRefusalsAndUndoableActionsAreLogged) {
  emit app_->toast(QStringLiteral("Saved"), QStringLiteral("success"));
  emit app_->toast(QStringLiteral("Could not do it"), QStringLiteral("warning"));
  emit app_->toast(QStringLiteral("Broke"), QStringLiteral("error"));
  emit app_->undoableToast(QStringLiteral("Deleted: A-1"), 5);
  const QVariantList log = app_->eventLog();
  ASSERT_EQ(log.size(), 3) << "a plain success is not news";
  EXPECT_EQ(log.at(0).toMap().value(QStringLiteral("kind")).toString(), QStringLiteral("undo"));
  EXPECT_EQ(log.at(1).toMap().value(QStringLiteral("kind")).toString(), QStringLiteral("error"));
  EXPECT_EQ(log.at(2).toMap().value(QStringLiteral("kind")).toString(), QStringLiteral("warning"));

  for(int i = 0; i < 150; ++i) {
    app_->logEvent(QStringLiteral("error"), QStringLiteral("e%1").arg(i));
  }
  EXPECT_EQ(app_->eventLog().size(), 100);
}

// APP-225: a toast with an action is gone in seconds; what it said stays in
// the log, and one about tasks opens them.
TEST_F(SyncVisibility, ToastsWithAnActionAreLogged) {
  emit app_->settingsReset(QStringLiteral("Settings reset"));
  emit app_->safetyNotice(QStringLiteral("stale"), QStringLiteral("Stuck"), QStringLiteral("A-1 has not moved"), {QStringLiteral("A-1")});
  emit app_->updateAvailable(QStringLiteral("9.9.9"), QStringLiteral("https://example.invalid"));
  emit app_->updateReadyToInstall(QStringLiteral("9.9.9"), QStringLiteral("abc"));
  const QVariantList log = app_->eventLog();
  ASSERT_EQ(log.size(), 4);
  const QVariantMap ready = log.at(0).toMap();
  EXPECT_TRUE(ready.value(QStringLiteral("message")).toString().contains(QStringLiteral("9.9.9")));
  EXPECT_EQ(ready.value(QStringLiteral("route")).toString(), QStringLiteral("settings:about"));
  EXPECT_EQ(log.at(1).toMap().value(QStringLiteral("route")).toString(), QStringLiteral("settings:about"));
  const QVariantMap safety = log.at(2).toMap();
  EXPECT_EQ(safety.value(QStringLiteral("message")).toString(), QStringLiteral("Stuck · A-1 has not moved"));
  EXPECT_EQ(safety.value(QStringLiteral("taskIds")).toStringList(), QStringList{QStringLiteral("A-1")});
  EXPECT_EQ(log.at(3).toMap().value(QStringLiteral("kind")).toString(), QStringLiteral("undo"));
}

TEST_F(SyncVisibility, SyncingIsTrueWhileAPullIsOut) {
  heap::testing::FakeHttpServer gitea;
  gitea.route("GET /api/v1/repos/acme/web/issues", {200, "[]", {}});
  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QStringLiteral("tok"));
  QJsonObject settings;
  settings.insert(QStringLiteral("integrations"),
                  QJsonObject{{QStringLiteral("gitea"),
                               QJsonObject{{QStringLiteral("connected"), true},
                                           {QStringLiteral("host"), gitea.base()},
                                           {QStringLiteral("repo"), QStringLiteral("acme/web")}}}});
  app_->setAppSettingsJson(QString::fromUtf8(QJsonDocument(settings).toJson(QJsonDocument::Compact)));

  QSignalSpy changed(app_.get(), &AppController::syncingChanged);
  EXPECT_FALSE(app_->syncing());
  app_->syncProvider(QStringLiteral("gitea"));
  EXPECT_TRUE(app_->syncing());
  ASSERT_TRUE(heap::testing::waitUntil([this]() {
    return !app_->syncing();
  })) << "the flag outlived the answer";
  EXPECT_EQ(changed.count(), 2);
}

TEST_F(SyncVisibility, AFailedPullIsLoggedWithTheWayToTheIntegrations) {
  heap::testing::FakeHttpServer gitea;
  gitea.route("GET /api/v1/repos/acme/web/issues", {404, R"({"message":"boom"})", {}});
  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QStringLiteral("tok"));
  QJsonObject settings;
  settings.insert(QStringLiteral("integrations"),
                  QJsonObject{{QStringLiteral("gitea"),
                               QJsonObject{{QStringLiteral("connected"), true},
                                           {QStringLiteral("host"), gitea.base()},
                                           {QStringLiteral("repo"), QStringLiteral("acme/web")}}}});
  app_->setAppSettingsJson(QString::fromUtf8(QJsonDocument(settings).toJson(QJsonDocument::Compact)));
  app_->syncProvider(QStringLiteral("gitea"));
  ASSERT_TRUE(heap::testing::waitUntil([this]() {
    return !app_->eventLog().isEmpty();
  }));
  const QVariantList log = app_->eventLog();
  ASSERT_EQ(log.size(), 1) << "logged twice: once by the hook, once with the route";
  EXPECT_EQ(log.first().toMap().value(QStringLiteral("route")).toString(), QStringLiteral("settings:integrations"));
  EXPECT_FALSE(app_->syncing());
}

}  // namespace syncvis

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  QApplication qapp(argc, argv);

  const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  if(!appData.isEmpty()) {
    QFile::remove(appData + QStringLiteral("/state.json"));
    QFile::remove(appData + QStringLiteral("/secrets.json"));
  }

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
