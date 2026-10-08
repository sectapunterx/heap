// Writing to a tracker is opt-in, per tracker (APP-243), and every write that
// is allowed is checked against the tracker first (APP-204). Tracker traffic
// goes to a local FakeHttpServer, never a live API; "nothing was written" is
// asserted on what that server actually received.

#include "AppController.h"
#include "FakeHttpServer.h"
#include "Models.h"

#include "integrations/IntegrationTypes.h"
#include "integrations/JiraProvider.h"
#include "integrations/ProviderRegistry.h"
#include "integrations/RestIssueProvider.h"
#include "integrations/SyncState.h"

#include <QApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkProxy>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

#include <algorithm>
#include <memory>

namespace trackerwrites {

using heap::integrations::ExternalTask;
using heap::testing::FakeHttpServer;

// Spin the event loop for a while: long enough for a request heap was going to
// make to reach the fake server.
void settle(int ms = 400) {
  heap::testing::waitUntil(
      []() {
        return false;
      },
      ms);
}

// One write-capable tracker, as the fake server needs to see it.
struct Tracker {
  QString id;
  QString cardId;
  QString externalId;
  QString project;      // the card's own project ("" = the configured one)
  QString remoteOpen;   // the status a pull reports for an open issue
  QByteArray checkKey;  // the fresh look before a write
  QByteArray writeKey;  // the write itself
};

Tracker trackerFor(const QString& id) {
  if(id == QStringLiteral("gitlab")) {
    return {id,
            QStringLiteral("gitlab-5"),
            QStringLiteral("5"),
            QString(),
            QStringLiteral("opened"),
            "GET /api/v4/projects/42/issues/5",
            "PUT /api/v4/projects/42/issues/5"};
  }
  if(id == QStringLiteral("jira")) {
    return {id,
            QStringLiteral("jira-HT-5"),
            QStringLiteral("HT-5"),
            QStringLiteral("HT"),
            QStringLiteral("To Do"),
            "GET /rest/api/3/issue/HT-5",
            "POST /rest/api/3/issue/HT-5/transitions"};
  }
  // Gitea and Forgejo share one API.
  return {id,
          id + QStringLiteral("-5"),
          QStringLiteral("5"),
          QStringLiteral("acme/web"),
          QStringLiteral("open"),
          "GET /api/v1/repos/acme/web/issues/5",
          "PATCH /api/v1/repos/acme/web/issues/5"};
}

class TrackerWrites : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<::AppController>();
    app_->tasks()->reset({});
    app_->setLanguage(QStringLiteral("en"));
    app_->setAppSettingsJson(QStringLiteral("{}"));
  }

  void TearDown() override {
    app_->setAppSettingsJson(QStringLiteral("{}"));
    for(const char* provider : {"gitea", "forgejo", "gitlab", "jira", "github"}) {
      app_->setIntegrationSecret(QString::fromLatin1(provider), QStringLiteral("token"), QString());
    }
    app_.reset();
  }

  void writeConfig(const QString& providerId, const QJsonObject& cfg) {
    QJsonObject settings = QJsonDocument::fromJson(app_->appSettingsJson().toUtf8()).object();
    QJsonObject integrations = settings.value(QStringLiteral("integrations")).toObject();
    integrations.insert(providerId, cfg);
    settings.insert(QStringLiteral("integrations"), integrations);
    app_->setAppSettingsJson(QString::fromUtf8(QJsonDocument(settings).toJson(QJsonDocument::Compact)));
  }

  // Connect a tracker to `server`, with its write switch on or off. Every
  // route a write would need answers as if all is well, so a missing request
  // can only mean heap chose not to make it.
  void connectTracker(const Tracker& tr, FakeHttpServer& server, bool writes, bool selfScope = false) {
    app_->setIntegrationSecret(tr.id, QStringLiteral("token"), QStringLiteral("tok"));
    QJsonObject cfg{{QStringLiteral("connected"), true}, {QStringLiteral("writeStatus"), writes}};
    if(tr.id == QStringLiteral("jira")) {
      cfg.insert(QStringLiteral("baseUrl"), server.base());
      cfg.insert(QStringLiteral("email"), QStringLiteral("me@example.com"));
      server.route("GET /rest/api/2/serverInfo", {200, R"({"deploymentType":"Cloud"})", {}});
      server.route("GET /rest/api/3/issue/HT-5", {200, R"({"fields":{"status":{"name":"To Do"}}})", {}});
      server.route("POST /rest/api/3/search/jql",
                   {200, R"({"issues":[{"key":"HT-5","fields":{"summary":"five","status":{"name":"To Do"}}}]})", {}});
      server.route("GET /rest/api/3/issue/HT-5/transitions",
                   {200, R"({"transitions":[{"id":"31","to":{"name":"Done"}},{"id":"21","to":{"name":"In Progress"}}]})", {}});
      server.route("POST /rest/api/3/issue/HT-5/transitions", {204, "", {}});
    } else if(tr.id == QStringLiteral("gitlab")) {
      cfg.insert(QStringLiteral("host"), server.base());
      cfg.insert(QStringLiteral("projectId"), QStringLiteral("42"));
      server.route("GET /api/v4/projects/42/issues", {200, R"([{"iid":5,"title":"five","state":"opened"}])", {}});
      server.route("GET /api/v4/projects/42/issues/5", {200, R"({"iid":5,"title":"five","state":"opened"})", {}});
      server.route("PUT /api/v4/projects/42/issues/5", {200, R"({"iid":5,"title":"five","state":"closed"})", {}});
    } else {
      cfg.insert(QStringLiteral("host"), server.base());
      cfg.insert(QStringLiteral("repo"), selfScope ? QString() : QStringLiteral("acme/web"));
      server.route("GET /api/v1/user", {200, R"({"login":"me"})", {}});
      server.route("GET /api/v1/repos/acme/web/issues", {200, "[" + giteaIssue(QStringLiteral("open")) + "]", {}});
      server.route("GET /api/v1/repos/acme/web/issues/5", {200, giteaIssue(QStringLiteral("open")), {}});
      server.route("PATCH /api/v1/repos/acme/web/issues/5", {200, giteaIssue(QStringLiteral("closed")), {}});
    }
    writeConfig(tr.id, cfg);
  }

  static QByteArray giteaIssue(const QString& state, const QString& assignee = QStringLiteral("me")) {
    return QStringLiteral(
               R"({"number":5,"title":"five","body":"","state":"%1","html_url":"https://gitea.example.com/acme/web/issues/5","repository":{"full_name":"acme/web"},"assignees":[{"login":"%2"}]})")
        .arg(state, assignee)
        .toUtf8();
  }

  // A card as the last pull left it: in To Do, the tracker's status known.
  Task card(const Tracker& tr) const {
    Task t;
    t.id = tr.cardId;
    t.title = QStringLiteral("five");
    t.status = QStringLiteral("todo");
    t.externalId = tr.externalId;
    t.externalProvider = tr.id;
    t.externalUrl = QStringLiteral("https://tracker.example.com/") + tr.externalId;
    t.externalMeta.project = tr.project;
    t.externalMeta.status = tr.remoteOpen;
    t.externalMeta.column = QStringLiteral("todo");
    t.externalMeta.title = t.title;
    return t;
  }

  void add(const Task& t) {
    QVector<Task> all = app_->tasks()->items();
    all.append(t);
    app_->tasks()->reset(all);
  }

  const Task* task(const QString& id) const {
    const int row = app_->tasks()->indexOfId(id);
    return row >= 0 ? &app_->tasks()->items().at(row) : nullptr;
  }

  void edit(const QString& id, const std::function<void(Task&)>& change) {
    Task t = *task(id);
    change(t);
    app_->tasks()->upsert(t);
  }

  static int count(const FakeHttpServer& server, const QByteArray& key) {
    return static_cast<int>(server.seen().count(key));
  }

  std::unique_ptr<::AppController> app_;
};

const char* const kWriteCapable[] = {"gitea", "forgejo", "gitlab", "jira"};

// ── APP-243: off by default ──

TEST_F(TrackerWrites, EveryTrackerStartsWithWritesOff) {
  EXPECT_TRUE(app_->trackerWriteProviders().isEmpty());
  QStringList withSwitch;
  for(const QVariant& v : app_->integrationCatalog()) {
    const QVariantMap m = v.toMap();
    const QString id = m.value(QStringLiteral("id")).toString();
    EXPECT_FALSE(app_->trackerWriteEnabled(id)) << id.toStdString();
    if(m.value(QStringLiteral("writesStatus")).toBool()) {
      withSwitch.append(id);
    }
  }
  withSwitch.sort();
  EXPECT_EQ(withSwitch,
            QStringList({QStringLiteral("forgejo"),
                         QStringLiteral("gitea"),
                         QStringLiteral("github"),
                         QStringLiteral("gitlab"),
                         QStringLiteral("jira")}));
  // A pull-only tracker cannot be switched on by a hand-edited setting.
  writeConfig(QStringLiteral("trello"), QJsonObject{{QStringLiteral("writeStatus"), true}});
  EXPECT_FALSE(app_->trackerWriteEnabled(QStringLiteral("trello")));

  // The settings switch: per tracker, and only where there is one.
  app_->setTrackerWriteEnabled(QStringLiteral("gitlab"), true);
  app_->setTrackerWriteEnabled(QStringLiteral("todoist"), true);
  EXPECT_EQ(app_->trackerWriteProviders(), QStringList{QStringLiteral("gitlab")});
  app_->setTrackerWriteEnabled(QStringLiteral("gitlab"), false);
  EXPECT_TRUE(app_->trackerWriteProviders().isEmpty());
}

TEST_F(TrackerWrites, Off_MoveMoveToAndUndoWriteNothing_ForEveryWritableTracker) {
  for(const char* id : kWriteCapable) {
    SCOPED_TRACE(id);
    app_->tasks()->reset({});
    FakeHttpServer server;
    const Tracker tr = trackerFor(QString::fromLatin1(id));
    connectTracker(tr, server, /*writes=*/false);
    add(card(tr));

    app_->moveTask(tr.cardId, QStringLiteral("done"));
    EXPECT_EQ(task(tr.cardId)->status, QStringLiteral("done")) << "the local move itself was refused";
    app_->moveTaskTo(tr.cardId, QStringLiteral("prog"), QString());
    EXPECT_EQ(task(tr.cardId)->status, QStringLiteral("prog"));
    app_->undo();
    settle();

    EXPECT_EQ(count(server, tr.writeKey), 0) << "a write went out with the switch off";
    EXPECT_EQ(count(server, tr.checkKey), 0) << "the tracker was asked about a write that is off";
    EXPECT_TRUE(task(tr.cardId)->externalMeta.unsyncedStatus.isEmpty()) << "a local move reads as unsent";
    EXPECT_FALSE(task(tr.cardId)->externalMeta.pushQueued) << "a local move was queued for later";
  }
}

TEST_F(TrackerWrites, On_MoveSendsTheTransitionAfterTheCheck_ForEveryWritableTracker) {
  for(const char* id : kWriteCapable) {
    SCOPED_TRACE(id);
    app_->tasks()->reset({});
    FakeHttpServer server;
    const Tracker tr = trackerFor(QString::fromLatin1(id));
    connectTracker(tr, server, /*writes=*/true);
    add(card(tr));
    QSignalSpy asked(app_.get(), &::AppController::trackerPushNeedsConfirm);

    app_->moveTask(tr.cardId, QStringLiteral("done"));
    ASSERT_TRUE(heap::testing::waitUntil([&]() {
      return count(server, tr.writeKey) == 1;
    })) << "the transition was never sent";
    const auto& seen = server.seen();
    EXPECT_LT(seen.indexOf(tr.checkKey), seen.indexOf(tr.writeKey)) << "written before it was checked";
    EXPECT_EQ(asked.count(), 0) << "an issue in the filter and in step needed no question";
    EXPECT_TRUE(heap::testing::waitUntil([&]() {
      return task(tr.cardId)->externalMeta.unsyncedStatus.isEmpty();
    }));
  }
}

TEST_F(TrackerWrites, SwitchingBackAndForth) {
  FakeHttpServer server;
  const Tracker tr = trackerFor(QStringLiteral("gitea"));
  connectTracker(tr, server, true);
  add(card(tr));
  app_->moveTask(tr.cardId, QStringLiteral("done"));
  // Answered, not only received: a settings write rebuilds the providers and
  // would drop a reply still in flight.
  ASSERT_TRUE(heap::testing::waitUntil([&]() {
    return count(server, tr.writeKey) == 1 && task(tr.cardId)->externalMeta.status == QStringLiteral("closed");
  }));

  // Off: the move back stays in heap.
  connectTracker(tr, server, false);
  ASSERT_FALSE(app_->trackerWriteEnabled(tr.id));
  app_->moveTask(tr.cardId, QStringLiteral("prog"));
  settle();
  EXPECT_EQ(count(server, tr.writeKey), 1);

  // On again: the next move goes out (its check sees the issue closed, as
  // the first write left it).
  server.route("GET /api/v1/repos/acme/web/issues/5", {200, giteaIssue(QStringLiteral("closed")), {}});
  connectTracker(tr, server, true);
  server.route("GET /api/v1/repos/acme/web/issues/5", {200, giteaIssue(QStringLiteral("closed")), {}});
  server.route("PATCH /api/v1/repos/acme/web/issues/5", {200, giteaIssue(QStringLiteral("open")), {}});
  app_->moveTask(tr.cardId, QStringLiteral("todo"));
  ASSERT_TRUE(heap::testing::waitUntil([&]() {
    return count(server, tr.writeKey) == 2;
  })) << server.seen().join(' ').toStdString()
      << " | unsynced=" << task(tr.cardId)->externalMeta.unsyncedStatus.toStdString()
      << " base=" << task(tr.cardId)->externalMeta.status.toStdString() << " queued=" << task(tr.cardId)->externalMeta.pushQueued
      << " oos=" << task(tr.cardId)->externalMeta.outOfScope << " conf=" << task(tr.cardId)->externalMeta.conflicts.join(",").toStdString();
}

TEST_F(TrackerWrites, OneTrackersSwitchDoesNotTurnOnAnother) {
  FakeHttpServer giteaServer;
  FakeHttpServer forgejoServer;
  const Tracker gitea = trackerFor(QStringLiteral("gitea"));
  const Tracker forgejo = trackerFor(QStringLiteral("forgejo"));
  connectTracker(gitea, giteaServer, true);
  connectTracker(forgejo, forgejoServer, false);
  add(card(gitea));
  add(card(forgejo));
  EXPECT_EQ(app_->trackerWriteProviders(), QStringList{QStringLiteral("gitea")});

  app_->moveTask(forgejo.cardId, QStringLiteral("done"));
  app_->moveTask(gitea.cardId, QStringLiteral("done"));
  ASSERT_TRUE(heap::testing::waitUntil([&]() {
    return count(giteaServer, gitea.writeKey) == 1;
  }));
  settle();
  EXPECT_TRUE(forgejoServer.seen().isEmpty()) << "Forgejo was written to on Gitea's switch";
}

// GitHub's API host is fixed, so it cannot be pointed at the fake server. With
// the fake standing in as the proxy, every attempt shows up as a CONNECT and
// none leaves the machine.
TEST_F(TrackerWrites, GitHub_OffAttemptsNothing_OnAsksTheTracker) {
  FakeHttpServer proxy;
  const quint16 port = static_cast<quint16>(QUrl(proxy.base()).port());
  QNetworkProxy::setApplicationProxy(QNetworkProxy(QNetworkProxy::HttpProxy, QStringLiteral("127.0.0.1"), port));
  app_->setIntegrationSecret(QStringLiteral("github"), QStringLiteral("token"), QStringLiteral("tok"));
  writeConfig(QStringLiteral("github"),
              QJsonObject{{QStringLiteral("connected"), true}, {QStringLiteral("repo"), QStringLiteral("acme/web")}});
  Task t;
  t.id = QStringLiteral("github-5");
  t.title = QStringLiteral("five");
  t.status = QStringLiteral("todo");
  t.externalId = QStringLiteral("5");
  t.externalProvider = QStringLiteral("github");
  t.externalMeta.project = QStringLiteral("acme/web");
  t.externalMeta.status = QStringLiteral("open");
  t.externalMeta.column = QStringLiteral("todo");
  add(t);

  app_->moveTask(QStringLiteral("github-5"), QStringLiteral("done"));
  settle();
  const bool quietWhenOff = proxy.seen().isEmpty();

  writeConfig(QStringLiteral("github"),
              QJsonObject{{QStringLiteral("connected"), true},
                          {QStringLiteral("repo"), QStringLiteral("acme/web")},
                          {QStringLiteral("writeStatus"), true}});
  app_->moveTask(QStringLiteral("github-5"), QStringLiteral("prog"));
  const bool asked = heap::testing::waitUntil([&proxy]() {
    return proxy.seen().contains("CONNECT api.github.com:443");
  });
  QNetworkProxy::setApplicationProxy(QNetworkProxy(QNetworkProxy::NoProxy));
  EXPECT_TRUE(quietWhenOff) << "GitHub was contacted with its switch off";
  EXPECT_TRUE(asked) << "GitHub was not asked with its switch on";
}

// The REST side of GitHub, against a copy of its descriptor aimed at the fake.
TEST_F(TrackerWrites, GitHubProvider_ChecksTheIssueAndItsAssignees) {
  FakeHttpServer server;
  heap::integrations::ProviderDescriptor d = *heap::integrations::findDescriptor(QStringLiteral("github"));
  d.baseUrlTemplate = server.base();
  server.route("GET /user", {200, R"({"login":"me"})", {}});
  server.route(
      "GET /repos/acme/web/issues/5",
      {200,
       R"({"number":5,"title":"five","state":"open","repository_url":"https://api.github.com/repos/acme/web","assignees":[{"login":"someone"},{"login":"me"}]})",
       {}});
  server.route(
      "GET /repos/acme/web/issues/6",
      {200,
       R"({"number":6,"title":"six","state":"closed","repository_url":"https://api.github.com/repos/acme/web","assignees":[{"login":"someone"}]})",
       {}});
  heap::integrations::RestIssueProvider p(d);
  p.setConfig({{QStringLiteral("token"), QStringLiteral("tok")}});  // "my issues"
  QVariantList answers;
  QObject::connect(&p,
                   &heap::integrations::IntegrationProvider::issueChecked,
                   &p,
                   [&answers](const QString& id, const QString&, bool ok, int, const QString&, const QString& status, int match) {
                     answers.append(QVariantMap{{"id", id}, {"ok", ok}, {"status", status}, {"match", match}});
                   });
  p.checkIssue(QStringLiteral("5"), QStringLiteral("acme/web"));
  ASSERT_TRUE(heap::testing::waitUntil([&answers]() {
    return answers.size() == 1;
  }));
  p.checkIssue(QStringLiteral("6"), QStringLiteral("acme/web"));
  ASSERT_TRUE(heap::testing::waitUntil([&answers]() {
    return answers.size() == 2;
  }));
  using IP = heap::integrations::IntegrationProvider;
  EXPECT_EQ(answers.at(0).toMap().value("status").toString(), QStringLiteral("open"));
  EXPECT_EQ(answers.at(0).toMap().value("match").toInt(), IP::FilterIn);
  EXPECT_EQ(answers.at(1).toMap().value("status").toString(), QStringLiteral("closed"));
  EXPECT_EQ(answers.at(1).toMap().value("match").toInt(), IP::FilterOut) << "reassigned, still read as mine";
  EXPECT_EQ(count(server, "GET /user"), 1) << "who I am is asked once";
}

// ── APP-243: the queue left by an older version ──

TEST_F(TrackerWrites, Off_AQueuedMoveIsNotSentByAPull_ButShowsAsUnsentUntilTheUserActs) {
  FakeHttpServer server;
  const Tracker tr = trackerFor(QStringLiteral("gitea"));
  Task queued = card(tr);
  queued.status = QStringLiteral("done");
  queued.externalMeta.unsyncedStatus = QStringLiteral("done");
  queued.externalMeta.pushQueued = true;
  add(queued);
  Task other = card(tr);
  other.id = QStringLiteral("gitea-6");
  other.externalId = QStringLiteral("6");
  other.status = QStringLiteral("prog");
  other.externalMeta.unsyncedStatus = QStringLiteral("prog");
  other.externalMeta.pushQueued = true;
  add(other);
  connectTracker(tr, server, false);

  app_->syncProvider(tr.id);
  ASSERT_TRUE(heap::testing::waitUntil([&]() {
    return count(server, "GET /api/v1/repos/acme/web/issues") >= 1;
  }));
  settle();
  EXPECT_EQ(count(server, tr.writeKey), 0) << "the queue was flushed with the switch off";
  EXPECT_EQ(task(tr.cardId)->status, QStringLiteral("done")) << "the pull took the unsent move back";
  EXPECT_TRUE(task(tr.cardId)->externalMeta.pushQueued);
  const int row = app_->tasks()->indexOfId(tr.cardId);
  EXPECT_EQ(app_->tasks()->data(app_->tasks()->index(row, 0), TaskModel::TicketRole).toMap().value(QStringLiteral("syncState")).toString(),
            QStringLiteral("queued"));

  // "Cancel": dropped, the column stays, nothing is sent.
  app_->discardTrackerPush(QStringLiteral("gitea-6"));
  EXPECT_TRUE(task(QStringLiteral("gitea-6"))->externalMeta.unsyncedStatus.isEmpty());
  EXPECT_FALSE(task(QStringLiteral("gitea-6"))->externalMeta.pushQueued);
  EXPECT_EQ(task(QStringLiteral("gitea-6"))->status, QStringLiteral("prog"));

  // "Send": the user's own explicit write, checked first, then sent.
  app_->retryTrackerPush(tr.cardId);
  ASSERT_TRUE(heap::testing::waitUntil([&]() {
    return count(server, tr.writeKey) == 1;
  }));
  EXPECT_GE(count(server, tr.checkKey), 1);
  settle();
  EXPECT_EQ(count(server, "PATCH /api/v1/repos/acme/web/issues/6"), 0);
}

TEST_F(TrackerWrites, Off_KeepingMyStatusInAConflictKeepsItHereOnly) {
  FakeHttpServer server;
  const Tracker tr = trackerFor(QStringLiteral("gitea"));
  connectTracker(tr, server, false);
  Task t = card(tr);
  t.status = QStringLiteral("prog");
  t.externalMeta.unsyncedStatus = QStringLiteral("prog");
  t.externalMeta.conflicts = {QStringLiteral("status")};
  add(t);
  app_->resolveTrackerConflictField(tr.cardId, QStringLiteral("status"), false);
  settle();
  EXPECT_EQ(server.seen().size(), 0);
  EXPECT_EQ(task(tr.cardId)->status, QStringLiteral("prog"));
  EXPECT_TRUE(task(tr.cardId)->externalMeta.unsyncedStatus.isEmpty());
  EXPECT_TRUE(task(tr.cardId)->externalMeta.conflicts.isEmpty());
}

// ── APP-243: the update from 0.7.x ──

TEST_F(TrackerWrites, UpdateFrom07x_EveryTrackerIsOff_AndTheNoticeComesOnce) {
  // A state.json as 0.7.x writes it (schema 11), with trackers connected and
  // no write switch anywhere — and no record of the notice.
  QFile fixture(QStringLiteral(HEAP_STATE_FIXTURES_DIR "/v0.5.4.json"));
  ASSERT_TRUE(fixture.open(QIODevice::ReadOnly));
  QJsonObject root = QJsonDocument::fromJson(fixture.readAll()).object();
  QJsonObject settings = root.value(QStringLiteral("settings")).toObject();
  QJsonObject appSettings = settings.value(QStringLiteral("app")).toObject();
  appSettings.insert(
      QStringLiteral("integrations"),
      QJsonDocument::fromJson(
          R"({"github":{"connected":true,"repo":"acme/web"},"gitea":{"connected":true,"host":"https://gitea.example.com"},"trello":{"connected":true}})")
          .object());
  settings.insert(QStringLiteral("app"), appSettings);
  settings.remove(QStringLiteral("trackerWriteNotice"));
  root.insert(QStringLiteral("settings"), settings);
  app_.reset();
  const QString statePath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/state.json");
  QFile::remove(statePath);
  {
    QFile out(statePath);
    ASSERT_TRUE(out.open(QIODevice::WriteOnly));
    out.write(QJsonDocument(root).toJson());
  }
  app_ = std::make_unique<::AppController>();
  ASSERT_TRUE(app_->appSettingsJson().contains(QStringLiteral("gitea.example.com"))) << "the 0.7.x state was not loaded";

  EXPECT_TRUE(app_->trackerWriteProviders().isEmpty());
  EXPECT_FALSE(app_->trackerWriteEnabled(QStringLiteral("github")));
  EXPECT_FALSE(app_->trackerWriteEnabled(QStringLiteral("gitea")));

  const QString notice = app_->trackerWriteNoticeOnce();
  EXPECT_TRUE(notice.contains(QStringLiteral("GitHub"))) << notice.toStdString();
  EXPECT_TRUE(notice.contains(QStringLiteral("Gitea"))) << notice.toStdString();
  EXPECT_FALSE(notice.contains(QStringLiteral("Trello"))) << "a pull-only tracker never wrote anything";
  EXPECT_TRUE(app_->trackerWriteNoticeOnce().isEmpty()) << "the notice came twice";

  // …and stays said across a restart.
  app_->flushSave();
  app_ = std::make_unique<::AppController>();
  EXPECT_TRUE(app_->trackerWriteNoticeOnce().isEmpty()) << "the notice came back after a restart";
}

TEST_F(TrackerWrites, FreshInstall_HasNoNoticeToGive) {
  EXPECT_TRUE(app_->trackerWriteNoticeOnce().isEmpty());
  // A tracker connected later is not told "no longer": it never did.
  writeConfig(QStringLiteral("github"), QJsonObject{{QStringLiteral("connected"), true}});
  EXPECT_TRUE(app_->trackerWriteNoticeOnce().isEmpty());
}

TEST_F(TrackerWrites, Off_APullDoesNotUndoALocalMove_AndTheTrackersStageStaysKnown) {
  const auto pulled = [](const QString& state) {
    ExternalTask e;
    e.providerId = QStringLiteral("gitea");
    e.externalId = QStringLiteral("5");
    e.url = QStringLiteral("https://gitea.example.com/acme/web/issues/5");
    e.title = QStringLiteral("five");
    e.status = state;
    e.project = QStringLiteral("acme/web");
    return e;
  };
  app_->mergeExternalTasks(QStringLiteral("gitea"), QStringLiteral("gitea-"), {pulled(QStringLiteral("open"))}, false);
  app_->moveTask(QStringLiteral("gitea-5"), QStringLiteral("review"));
  app_->mergeExternalTasks(QStringLiteral("gitea"), QStringLiteral("gitea-"), {pulled(QStringLiteral("closed"))}, false);
  EXPECT_EQ(task(QStringLiteral("gitea-5"))->status, QStringLiteral("review"));
  EXPECT_TRUE(task(QStringLiteral("gitea-5"))->externalMeta.conflicts.isEmpty());
  const int row = app_->tasks()->indexOfId(QStringLiteral("gitea-5"));
  const QVariantMap ticket = app_->tasks()->data(app_->tasks()->index(row, 0), TaskModel::TicketRole).toMap();
  EXPECT_EQ(ticket.value(QStringLiteral("remoteStatus")).toString(), QStringLiteral("closed"));
  EXPECT_EQ(ticket.value(QStringLiteral("remoteColumn")).toString(), QStringLiteral("done"));
  EXPECT_EQ(ticket.value(QStringLiteral("syncState")).toString(), QStringLiteral("synced"));
}

TEST(TrackerWritesPure, LocalOwnsColumnKeepsAPlacedCard) {
  using heap::integrations::mergeStatusOnPull;
  using heap::integrations::StatusPull;
  const QString open = QStringLiteral("open");
  const QString closed = QStringLiteral("closed");
  // Placed by the user, tracker moved: kept while heap does not write.
  EXPECT_EQ(mergeStatusOnPull(QStringLiteral("prog"), {}, open, closed, QStringLiteral("done"), QStringLiteral("todo"), true),
            StatusPull::Keep);
  EXPECT_EQ(mergeStatusOnPull(QStringLiteral("prog"), {}, open, closed, QStringLiteral("done"), QStringLiteral("todo"), false),
            StatusPull::TakeRemote);
  // Never placed: follows the tracker either way.
  EXPECT_EQ(mergeStatusOnPull(QStringLiteral("todo"), {}, open, closed, QStringLiteral("done"), QStringLiteral("todo"), true),
            StatusPull::TakeRemote);
  // An unsent move left over is not a conflict when nothing will be sent.
  EXPECT_EQ(
      mergeStatusOnPull(QStringLiteral("prog"), QStringLiteral("prog"), open, closed, QStringLiteral("done"), QStringLiteral("todo"), true),
      StatusPull::Keep);
}

// ── APP-204: outside the filter, gone ──

TEST_F(TrackerWrites, On_OutOfScopeOrGoneCardRefusesTheDropAndSendsNothing) {
  FakeHttpServer server;
  const Tracker tr = trackerFor(QStringLiteral("gitea"));
  connectTracker(tr, server, true);
  Task out = card(tr);
  out.externalMeta.outOfScope = true;
  add(out);
  Task gone = card(tr);
  gone.id = QStringLiteral("gitea-6");
  gone.externalId = QStringLiteral("6");
  gone.externalMeta.goneUpstream = true;
  add(gone);
  QSignalSpy refused(app_.get(), &::AppController::trackerReadOnlyMove);

  app_->moveTaskTo(tr.cardId, QStringLiteral("done"), QString());
  app_->moveTask(QStringLiteral("gitea-6"), QStringLiteral("done"));
  settle();
  EXPECT_EQ(task(tr.cardId)->status, QStringLiteral("todo")) << "the card did not snap back";
  EXPECT_EQ(task(QStringLiteral("gitea-6"))->status, QStringLiteral("todo"));
  EXPECT_TRUE(server.seen().isEmpty()) << "the tracker was written for a card that is not mine";
  ASSERT_EQ(refused.count(), 2);
  EXPECT_TRUE(refused.at(0).at(1).toString().contains(QStringLiteral("filter")));
  EXPECT_EQ(refused.at(0).at(2).toString(), out.externalUrl) << "no way to open the issue";

  // Local things still work on it.
  app_->setArchived(tr.cardId, true);
  EXPECT_TRUE(task(tr.cardId)->archived);
}

TEST_F(TrackerWrites, Off_OutOfScopeCardMovesLocally) {
  FakeHttpServer server;
  const Tracker tr = trackerFor(QStringLiteral("gitea"));
  connectTracker(tr, server, false);
  Task out = card(tr);
  out.externalMeta.outOfScope = true;
  add(out);
  app_->moveTask(tr.cardId, QStringLiteral("done"));
  settle();
  EXPECT_EQ(task(tr.cardId)->status, QStringLiteral("done"));
  EXPECT_TRUE(server.seen().isEmpty());
}

TEST_F(TrackerWrites, On_AQueuedMoveOfACardThatLeftTheFilterIsHeldNotSent) {
  FakeHttpServer server;
  const Tracker tr = trackerFor(QStringLiteral("gitea"));
  Task t = card(tr);
  t.status = QStringLiteral("done");
  t.externalMeta.unsyncedStatus = QStringLiteral("done");
  t.externalMeta.pushQueued = true;
  // Pulled under a filter that is not the one configured now: missing from
  // a complete pull, it is outside the filter.
  t.externalMeta.scope = QStringLiteral("an older filter");
  add(t);
  connectTracker(tr, server, true);
  server.route("GET /api/v1/repos/acme/web/issues", {200, "[]", {}});

  app_->syncProvider(tr.id);
  ASSERT_TRUE(heap::testing::waitUntil([&]() {
    return task(tr.cardId)->externalMeta.outOfScope;
  }));
  settle();
  EXPECT_EQ(count(server, tr.writeKey), 0) << "a move of a card that is not mine went out";
  EXPECT_EQ(count(server, tr.checkKey), 0);
  EXPECT_FALSE(task(tr.cardId)->externalMeta.pushQueued);
  EXPECT_EQ(task(tr.cardId)->externalMeta.unsyncedStatus, QStringLiteral("done")) << "the held move should read as unsent";
}

// ── APP-204: the check before a write ──

TEST_F(TrackerWrites, Check_ReassignedIssueAsksBeforeSending_AndOnlyConfirmationSends) {
  FakeHttpServer server;
  const Tracker tr = trackerFor(QStringLiteral("gitea"));
  connectTracker(tr, server, true, /*selfScope=*/true);
  server.route("GET /api/v1/repos/acme/web/issues/5", {200, giteaIssue(QStringLiteral("open"), QStringLiteral("someone")), {}});
  add(card(tr));
  QSignalSpy asked(app_.get(), &::AppController::trackerPushNeedsConfirm);

  app_->moveTask(tr.cardId, QStringLiteral("done"));
  ASSERT_TRUE(heap::testing::waitUntil([&asked]() {
    return asked.count() == 1;
  })) << "the user was not asked";
  settle();
  EXPECT_EQ(count(server, tr.writeKey), 0) << "sent without the user's word";
  EXPECT_EQ(asked.at(0).at(0).toString(), tr.cardId);
  EXPECT_EQ(asked.at(0).at(4).toString(), QStringLiteral("open")) << "the dialog must show the tracker's status now";
  EXPECT_TRUE(task(tr.cardId)->externalMeta.outOfScope);
  EXPECT_EQ(task(tr.cardId)->externalMeta.unsyncedStatus, QStringLiteral("done"));
  EXPECT_EQ(task(tr.cardId)->status, QStringLiteral("done"));

  // Cancel is doing nothing: still nothing sent.
  settle();
  EXPECT_EQ(count(server, tr.writeKey), 0);

  // "Send anyway".
  app_->confirmTrackerPush(tr.cardId);
  ASSERT_TRUE(heap::testing::waitUntil([&]() {
    return count(server, tr.writeKey) == 1;
  }));
}

TEST_F(TrackerWrites, Check_JiraIssueOutsideTheJqlIsNotTransitioned) {
  FakeHttpServer server;
  const Tracker tr = trackerFor(QStringLiteral("jira"));
  connectTracker(tr, server, true);
  server.route("POST /rest/api/3/search/jql", {200, R"({"issues":[]})", {}});
  add(card(tr));
  QSignalSpy asked(app_.get(), &::AppController::trackerPushNeedsConfirm);

  app_->moveTask(tr.cardId, QStringLiteral("done"));
  ASSERT_TRUE(heap::testing::waitUntil([&asked]() {
    return asked.count() == 1;
  }));
  settle();
  EXPECT_EQ(count(server, tr.writeKey), 0);
  EXPECT_EQ(count(server, "GET /rest/api/3/issue/HT-5/transitions"), 0);
  const QByteArray search = server.lastRequest("POST /rest/api/3/search/jql").body;
  EXPECT_TRUE(search.contains("key = \\\"HT-5\\\" AND (assignee = currentUser())")) << search.toStdString();
}

TEST_F(TrackerWrites, Check_StatusChangedInTheTrackerIsAConflictNotAWrite) {
  for(const char* id : {"gitea", "jira"}) {
    SCOPED_TRACE(id);
    app_->tasks()->reset({});
    FakeHttpServer server;
    const Tracker tr = trackerFor(QString::fromLatin1(id));
    connectTracker(tr, server, true);
    if(tr.id == QStringLiteral("jira")) {
      server.route("GET /rest/api/3/issue/HT-5", {200, R"({"fields":{"status":{"name":"In Review"}}})", {}});
    } else {
      server.route("GET /api/v1/repos/acme/web/issues/5", {200, giteaIssue(QStringLiteral("closed")), {}});
    }
    add(card(tr));
    app_->moveTask(tr.cardId, QStringLiteral("prog"));
    ASSERT_TRUE(heap::testing::waitUntil([&]() {
      return task(tr.cardId)->externalMeta.conflicts.contains(QStringLiteral("status"));
    })) << "no conflict for a status the tracker changed";
    settle();
    EXPECT_EQ(count(server, tr.writeKey), 0) << "overwrote the tracker's move unseen";
    EXPECT_EQ(task(tr.cardId)->status, QStringLiteral("prog"));
    EXPECT_EQ(task(tr.cardId)->externalMeta.unsyncedStatus, QStringLiteral("prog"));

    // "Keep mine" is an explicit choice: now in step with what heap saw, it goes.
    app_->resolveTrackerConflictField(tr.cardId, QStringLiteral("status"), false);
    ASSERT_TRUE(heap::testing::waitUntil([&]() {
      return count(server, tr.writeKey) == 1;
    })) << "keeping mine did not send it";
  }
}

TEST(TrackerWritesPure, JiraJqlForOneIssue) {
  using heap::integrations::jiraJqlForIssue;
  EXPECT_EQ(jiraJqlForIssue(QStringLiteral("HT-5"), QString()), QStringLiteral(R"(key = "HT-5" AND (assignee = currentUser()))"));
  EXPECT_EQ(jiraJqlForIssue(QStringLiteral("HT-5"), QStringLiteral("project = HT and status != Done order by rank")),
            QStringLiteral(R"(key = "HT-5" AND (project = HT and status != Done))"));
  EXPECT_EQ(jiraJqlForIssue(QStringLiteral("HT-5"), QStringLiteral("ORDER BY created DESC")), QStringLiteral(R"(key = "HT-5")"));
}

}  // namespace trackerwrites

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  QApplication qapp(argc, argv);

  // A state.json left by an earlier run would say the notice was given.
  const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  if(!appData.isEmpty()) {
    QFile::remove(appData + QStringLiteral("/state.json"));
    QFile::remove(appData + QStringLiteral("/secrets.json"));
  }

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
