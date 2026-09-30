// Regression tests for the integration / release findings of the 2026-09-30
// end-to-end audit (INT-1…INT-10, PLAT-27, PLAT-28). Each test names the defect
// it pins. Tracker traffic goes to a local FakeHttpServer, never a live API.

#include "AppController.h"
#include "FakeHttpServer.h"
#include "Models.h"

#include "diag/IssueReport.h"
#include "integrations/IntegrationI18n.h"
#include "integrations/IntegrationTypes.h"
#include "integrations/OAuthRefresh.h"
#include "integrations/ProviderRegistry.h"
#include "integrations/TrackerMerge.h"
#include "update/Updater.h"

#include <QApplication>
#include <QDateTime>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTimeZone>

#include <gtest/gtest.h>

#include <memory>

namespace intaudit {

using heap::integrations::ExternalTask;

class IntAudit : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<::AppController>();
    app_->tasks()->reset({});
    app_->setLanguage(QStringLiteral("en"));
    app_->setAppSettingsJson(QStringLiteral("{}"));
  }

  void TearDown() override {
    app_->setAppSettingsJson(QStringLiteral("{}"));
    for(const char* f : {"token", "refreshToken"}) {
      app_->setIntegrationSecret(QStringLiteral("gitea"), QString::fromLatin1(f), QString());
    }
    app_.reset();
  }

  void writeIntegrationConfig(const QString& providerId, const QJsonObject& cfg) {
    QJsonObject settings = QJsonDocument::fromJson(app_->appSettingsJson().toUtf8()).object();
    QJsonObject integrations = settings.value(QStringLiteral("integrations")).toObject();
    integrations.insert(providerId, cfg);
    settings.insert(QStringLiteral("integrations"), integrations);
    app_->setAppSettingsJson(QString::fromUtf8(QJsonDocument(settings).toJson(QJsonDocument::Compact)));
  }

  QJsonObject readIntegrationConfig(const QString& providerId) const {
    return QJsonDocument::fromJson(app_->appSettingsJson().toUtf8())
        .object()
        .value(QStringLiteral("integrations"))
        .toObject()
        .value(providerId)
        .toObject();
  }

  static ExternalTask issue(const QString& number, const QString& status = QStringLiteral("open")) {
    ExternalTask e;
    e.providerId = QStringLiteral("github");
    e.externalId = number;
    e.url = QStringLiteral("https://github.com/acme/app/issues/") + number;
    e.title = QStringLiteral("title ") + number;
    e.body = QStringLiteral("body");
    e.status = status;
    e.project = QStringLiteral("acme/app");
    return e;
  }

  ::AppController::MergeStats merge(const QVector<ExternalTask>& issues, bool complete = true) {
    return app_->mergeExternalTasks(QStringLiteral("github"), QStringLiteral("gh-"), issues, complete);
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

  std::unique_ptr<::AppController> app_;
};

// ── INT-1: a filter change is "out of scope", not "gone upstream" ──

TEST_F(IntAudit, ScopeChange_MissingIssues_AreOutOfScopeNotGone) {
  writeIntegrationConfig(QStringLiteral("github"), QJsonObject{{QStringLiteral("repo"), QStringLiteral("acme/app")}});
  merge({issue("1"), issue("2")});
  ASSERT_NE(task("gh-1"), nullptr);

  // The user switches the card to "my issues": only #1 is assigned to them.
  writeIntegrationConfig(QStringLiteral("github"), QJsonObject{{QStringLiteral("repo"), QString()}});
  const auto stats = merge({issue("1")});
  EXPECT_EQ(stats.gone, 0) << "a filter change reported a live issue as deleted";
  EXPECT_EQ(stats.outOfScope, 1);
  EXPECT_FALSE(task("gh-2")->externalMeta.goneUpstream);
  EXPECT_TRUE(task("gh-2")->externalMeta.outOfScope);
  EXPECT_TRUE(ticketToVariant(*task("gh-2")).value(QStringLiteral("outOfScope")).toBool());
  EXPECT_EQ(app_->property("integrationStates").toMap().value(QStringLiteral("github")).toMap().value(QStringLiteral("outOfScope")).toInt(),
            1);

  // A second sync under the same new filter says nothing new about it.
  EXPECT_EQ(merge({issue("1")}).outOfScope, 0);

  // Back to the repo: #2 is in scope again and the mark goes.
  writeIntegrationConfig(QStringLiteral("github"), QJsonObject{{QStringLiteral("repo"), QStringLiteral("acme/app")}});
  merge({issue("1"), issue("2")});
  EXPECT_FALSE(task("gh-2")->externalMeta.outOfScope);
}

TEST_F(IntAudit, UnchangedScope_MissingIssue_IsGone) {
  writeIntegrationConfig(QStringLiteral("github"), QJsonObject{{QStringLiteral("repo"), QStringLiteral("acme/app")}});
  merge({issue("1"), issue("2")});
  const auto stats = merge({issue("1")});
  EXPECT_EQ(stats.gone, 1);
  EXPECT_TRUE(task("gh-2")->externalMeta.goneUpstream);
  EXPECT_FALSE(task("gh-2")->externalMeta.outOfScope);
}

TEST_F(IntAudit, CosmeticJqlEdit_IsNotAScopeChange) {
  const auto* d = heap::integrations::findDescriptor(QStringLiteral("jira"));
  ASSERT_NE(d, nullptr);
  const QString a = heap::integrations::scopeFingerprint(*d, {{QStringLiteral("jql"), QStringLiteral("project = HT")}});
  const QString b = heap::integrations::scopeFingerprint(*d, {{QStringLiteral("jql"), QStringLiteral("  project  =  HT ")}});
  const QString c = heap::integrations::scopeFingerprint(*d, {{QStringLiteral("jql"), QStringLiteral("project = HT AND key != HT-9")}});
  EXPECT_EQ(a, b);
  EXPECT_NE(a, c);
  // A token or an OAuth app is how heap signs in, not which issues exist.
  EXPECT_EQ(a,
            heap::integrations::scopeFingerprint(
                *d, {{QStringLiteral("jql"), QStringLiteral("project = HT")}, {QStringLiteral("clientId"), QStringLiteral("x")}}));
}

TEST_F(IntAudit, ArchiveOutOfScope_ArchivesOnlyThoseCards) {
  writeIntegrationConfig(QStringLiteral("github"), QJsonObject{{QStringLiteral("repo"), QStringLiteral("acme/app")}});
  merge({issue("1"), issue("2")});
  writeIntegrationConfig(QStringLiteral("github"), QJsonObject{{QStringLiteral("repo"), QStringLiteral("acme/other")}});
  merge({issue("1")});
  app_->archiveOutOfScope(QStringLiteral("github"));
  EXPECT_TRUE(task("gh-2")->archived);
  EXPECT_FALSE(task("gh-1")->archived);
}

// ── INT-2: priority is three-way ──

TEST_F(IntAudit, LocalPriorityEdit_SurvivesASyncThatDidNotTouchIt) {
  ExternalTask e = issue("9");
  e.priority = QStringLiteral("Medium");
  merge({e});
  ASSERT_EQ(task("gh-9")->priority, QStringLiteral("P2"));
  edit(QStringLiteral("gh-9"), [](Task& t) {
    t.priority = QStringLiteral("P0");
  });
  const auto stats = merge({e});
  EXPECT_EQ(task("gh-9")->priority, QStringLiteral("P0")) << "a local priority was reverted by an unchanged tracker";
  EXPECT_EQ(stats.conflicts, 0);
}

TEST_F(IntAudit, BothSidesChangedPriority_KeepsLocalAndCountsAConflict) {
  ExternalTask e = issue("5");
  e.priority = QStringLiteral("Medium");
  merge({e});
  edit(QStringLiteral("gh-5"), [](Task& t) {
    t.priority = QStringLiteral("P1");
  });
  e.priority = QStringLiteral("Lowest");
  const auto stats = merge({e});
  EXPECT_EQ(task("gh-5")->priority, QStringLiteral("P1"));
  EXPECT_EQ(stats.conflicts, 1);
  EXPECT_TRUE(task("gh-5")->externalMeta.conflicts.contains(QStringLiteral("priority")));

  app_->resolveTrackerConflict(QStringLiteral("gh-5"), /*useTracker=*/true);
  EXPECT_EQ(task("gh-5")->priority, QStringLiteral("P3"));
  EXPECT_TRUE(task("gh-5")->externalMeta.conflicts.isEmpty());
}

TEST_F(IntAudit, RemotePriorityChange_WithoutLocalEdit_IsTaken) {
  ExternalTask e = issue("4");
  e.priority = QStringLiteral("Medium");
  merge({e});
  e.priority = QStringLiteral("Highest");
  merge({e});
  EXPECT_EQ(task("gh-4")->priority, QStringLiteral("P0"));
}

TEST_F(IntAudit, CardWithoutAPriorityBase_KeepsItsLocalPriority) {
  // Stored by a build that kept no priority base, then edited locally.
  Task t;
  t.id = QStringLiteral("gh-3");
  t.title = QStringLiteral("title 3");
  t.desc = QStringLiteral("body");
  t.status = QStringLiteral("todo");
  t.priority = QStringLiteral("P0");
  t.externalId = QStringLiteral("3");
  t.externalProvider = QStringLiteral("github");
  t.externalUrl = issue("3").url;
  t.externalMeta.title = t.title;
  t.externalMeta.body = t.desc;
  t.externalMeta.status = QStringLiteral("open");
  app_->tasks()->reset({t});
  ExternalTask e = issue("3");
  e.priority = QStringLiteral("Medium");
  merge({e});
  EXPECT_EQ(task("gh-3")->priority, QStringLiteral("P0"));
  EXPECT_EQ(task("gh-3")->externalMeta.priority, QStringLiteral("P2"));
}

// ── INT-3: labels are three-way ──

TEST_F(IntAudit, LabelRemovedUpstream_IsRemovedHere_LocalOnesStay) {
  ExternalTask e = issue("11");
  e.labels = {QStringLiteral("bug")};
  merge({e});
  edit(QStringLiteral("gh-11"), [](Task& t) {
    t.labels.append(Label{QStringLiteral("mine"), QString()});
  });
  e.labels = {QStringLiteral("enhancement")};
  merge({e});
  QStringList names;
  for(const Label& l : task("gh-11")->labels) {
    names.append(l.id);
  }
  EXPECT_EQ(names, (QStringList{QStringLiteral("mine"), QStringLiteral("enhancement")}));
}

TEST_F(IntAudit, LabelRemovedLocally_StaysRemovedWhileTheTrackerKeepsIt) {
  ExternalTask e = issue("12");
  e.labels = {QStringLiteral("bug"), QStringLiteral("ui")};
  merge({e});
  edit(QStringLiteral("gh-12"), [](Task& t) {
    t.labels.removeIf([](const Label& l) {
      return l.id == QStringLiteral("ui");
    });
  });
  merge({e});
  ASSERT_EQ(task("gh-12")->labels.size(), 1);
  EXPECT_EQ(task("gh-12")->labels.at(0).id, QStringLiteral("bug"));
}

TEST(TrackerMerge, LabelsWithoutABase_OnlyGain) {
  const QVector<Label> merged =
      heap::integrations::mergeLabels({Label{QStringLiteral("a"), QString()}}, {}, {QStringLiteral("b")}, {{QStringLiteral("b"), "#fff"}});
  ASSERT_EQ(merged.size(), 2);
  EXPECT_EQ(merged.at(1).color, QStringLiteral("#fff"));
}

// ── INT-4: conflicts are named, visible and resolvable ──

TEST_F(IntAudit, TitleConflict_IsNamedFlaggedAndResolvable) {
  ExternalTask e = issue("5");
  merge({e});
  edit(QStringLiteral("gh-5"), [](Task& t) {
    t.title = QStringLiteral("mine");
  });
  e.title = QStringLiteral("theirs");
  const auto stats = merge({e});
  EXPECT_EQ(stats.conflictKeys, QStringList{QStringLiteral("#5")});
  const QVariantMap ticket = ticketToVariant(*task("gh-5"));
  EXPECT_TRUE(ticket.value(QStringLiteral("conflict")).toBool());
  EXPECT_EQ(ticket.value(QStringLiteral("remoteTitle")).toString(), QStringLiteral("theirs"));
  EXPECT_EQ(task("gh-5")->title, QStringLiteral("mine"));

  // Still flagged on a later sync that changes nothing.
  merge({e});
  EXPECT_TRUE(ticketToVariant(*task("gh-5")).value(QStringLiteral("conflict")).toBool());

  app_->resolveTrackerConflict(QStringLiteral("gh-5"), /*useTracker=*/false);
  EXPECT_EQ(task("gh-5")->title, QStringLiteral("mine"));
  EXPECT_FALSE(ticketToVariant(*task("gh-5")).value(QStringLiteral("conflict")).toBool());

  // The next upstream edit of the same field is flagged again, not ignored.
  e.title = QStringLiteral("theirs, again");
  EXPECT_EQ(merge({e}).conflicts, 1);
  app_->resolveTrackerConflict(QStringLiteral("gh-5"), /*useTracker=*/true);
  EXPECT_EQ(task("gh-5")->title, QStringLiteral("theirs, again"));
}

TEST_F(IntAudit, Toast_NamesTheConflictingCard_AndNeverSaysUpToDateNextToNews) {
  // INT-7's "up to date · 1 no longer in the tracker" and INT-4's nameless
  // conflict toast both come from the tasksFetched handler, which a real pull
  // drives. Checked through the strings it is built from.
  EXPECT_TRUE(app_->tr_(QStringLiteral("sync.conflicts")).contains(QStringLiteral("%2")));
  EXPECT_NE(app_->tr_(QStringLiteral("sync.headline")), QStringLiteral("sync.headline"));
}

// ── INT-5: only a refused grant ends the session ──

TEST(OAuthRefresh, OnlyARefusedGrantIsDefinitive) {
  using heap::integrations::isDefinitiveGrantFailure;
  EXPECT_TRUE(isDefinitiveGrantFailure(400, R"({"error":"invalid_grant"})"));
  EXPECT_TRUE(isDefinitiveGrantFailure(401, "{}"));
  EXPECT_TRUE(isDefinitiveGrantFailure(403, R"({"error":"invalid_grant"})"));
  EXPECT_FALSE(isDefinitiveGrantFailure(0, {}));  // offline, DNS, timeout
  EXPECT_FALSE(isDefinitiveGrantFailure(503, "<html>maintenance</html>"));
  EXPECT_FALSE(isDefinitiveGrantFailure(429, "{}"));
  EXPECT_FALSE(isDefinitiveGrantFailure(200, "<html>captive portal</html>"));
}

class OAuthGitea : public IntAudit {
 protected:
  void connectExpiredSession(const QString& host) {
    app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QStringLiteral("old"));
    app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("refreshToken"), QStringLiteral("r1"));
    writeIntegrationConfig(QStringLiteral("gitea"),
                           QJsonObject{
                               {QStringLiteral("connected"), true},
                               {QStringLiteral("authMode"), QStringLiteral("oauth")},
                               {QStringLiteral("clientId"), QStringLiteral("cid")},
                               {QStringLiteral("host"), host},
                               {QStringLiteral("repo"), QStringLiteral("acme/web")},
                               {QStringLiteral("tokenExpiresAt"), QStringLiteral("2020-01-01T00:00:00Z")},
                           });
  }

  bool offline() const {
    return app_->property("integrationStates").toMap().value(QStringLiteral("gitea")).toMap().value(QStringLiteral("offline")).toBool();
  }
};

TEST_F(OAuthGitea, RefreshWithNoNetwork_StaysConnectedAndGoesOffline) {
  connectExpiredSession(QStringLiteral("http://127.0.0.1:1"));  // nothing listens there
  app_->syncProvider(QStringLiteral("gitea"));
  ASSERT_TRUE(heap::testing::waitUntil([this]() {
    return offline();
  })) << "a refresh that got no answer did not report offline";
  EXPECT_TRUE(readIntegrationConfig(QStringLiteral("gitea")).value(QStringLiteral("connected")).toBool())
      << "a network failure signed the user out";
}

TEST_F(OAuthGitea, RefreshA5xx_StaysConnected) {
  heap::testing::FakeHttpServer server;
  server.route("POST /login/oauth/access_token", {503, "<html>down</html>", {}});
  connectExpiredSession(server.base());
  app_->syncProvider(QStringLiteral("gitea"));
  ASSERT_TRUE(heap::testing::waitUntil([this]() {
    return offline();
  }));
  EXPECT_TRUE(readIntegrationConfig(QStringLiteral("gitea")).value(QStringLiteral("connected")).toBool());
}

TEST_F(OAuthGitea, RefreshInvalidGrant_Disconnects) {
  heap::testing::FakeHttpServer server;
  server.route("POST /login/oauth/access_token", {400, R"({"error":"invalid_grant"})", {}});
  connectExpiredSession(server.base());
  app_->syncProvider(QStringLiteral("gitea"));
  ASSERT_TRUE(heap::testing::waitUntil([this]() {
    return !readIntegrationConfig(QStringLiteral("gitea")).value(QStringLiteral("connected")).toBool();
  })) << "a revoked grant left the card connected";
  EXPECT_FALSE(offline());
}

// ── INT-10: the expiry is stored in UTC with its offset ──

TEST_F(OAuthGitea, RenewedExpiry_IsStoredInUtc) {
  heap::testing::FakeHttpServer server;
  server.route("POST /login/oauth/access_token", {200, R"({"access_token":"new","refresh_token":"r2","expires_in":3600})", {}});
  server.route("GET /api/v1/repos/acme/web/issues", {200, "[]", {}});
  connectExpiredSession(server.base());
  app_->syncProvider(QStringLiteral("gitea"));
  ASSERT_TRUE(heap::testing::waitUntil([this]() {
    return readIntegrationConfig(QStringLiteral("gitea")).value(QStringLiteral("tokenExpiresAt")).toString() !=
           QStringLiteral("2020-01-01T00:00:00Z");
  }));
  const QString stored = readIntegrationConfig(QStringLiteral("gitea")).value(QStringLiteral("tokenExpiresAt")).toString();
  EXPECT_TRUE(stored.endsWith(QChar('Z'))) << stored.toStdString();
  const qint64 left = QDateTime::currentDateTimeUtc().secsTo(heap::integrations::expiryFromString(stored));
  EXPECT_GT(left, 3500);
  EXPECT_LT(left, 3700);
}

TEST(OAuthRefresh, ExpiryRoundTripsAndReadsOldLocalValues) {
  const QDateTime at(QDate(2026, 9, 30), QTime(0, 38, 4), QTimeZone::UTC);
  EXPECT_EQ(heap::integrations::expiryToString(at), QStringLiteral("2026-09-30T00:38:04Z"));
  EXPECT_EQ(heap::integrations::expiryFromString(heap::integrations::expiryToString(at)), at);
  // What 0.5.2 wrote: local wall time, no offset. Read as local, as meant.
  const QDateTime old = heap::integrations::expiryFromString(QStringLiteral("2026-09-30T00:38:04"));
  ASSERT_TRUE(old.isValid());
  EXPECT_EQ(old, QDateTime(QDate(2026, 9, 30), QTime(0, 38, 4)));
  EXPECT_TRUE(heap::integrations::expiryToString(QDateTime()).isEmpty());
}

// ── INT-6: a move made while disconnected is queued, then sent ──

TEST_F(IntAudit, MoveWhileDisconnected_IsQueuedThenPushedAfterTheNextPull) {
  Task t;
  t.id = QStringLiteral("gitea-5");
  t.title = QStringLiteral("five");
  t.status = QStringLiteral("todo");
  t.externalId = QStringLiteral("5");
  t.externalProvider = QStringLiteral("gitea");
  t.externalUrl = QStringLiteral("https://gitea.example.com/acme/web/issues/5");
  t.externalMeta.status = QStringLiteral("open");
  t.externalMeta.column = QStringLiteral("todo");
  t.externalMeta.title = t.title;
  app_->tasks()->reset({t});

  app_->moveTask(QStringLiteral("gitea-5"), QStringLiteral("done"));
  ASSERT_TRUE(task("gitea-5")->externalMeta.pushQueued) << "a move with nowhere to go vanished";
  EXPECT_EQ(task("gitea-5")->externalMeta.unsyncedStatus, QStringLiteral("done"));
  EXPECT_TRUE(ticketToVariant(*task("gitea-5")).value(QStringLiteral("unsynced")).toBool());

  heap::testing::FakeHttpServer gitea;
  gitea.route(
      "GET /api/v1/repos/acme/web/issues",
      {200, R"([{"number":5,"title":"five","body":"","state":"open","html_url":"https://gitea.example.com/acme/web/issues/5"}])", {}});
  gitea.route("PATCH /api/v1/repos/acme/web/issues/5", {200, "{}", {}});
  app_->setIntegrationSecret(QStringLiteral("gitea"), QStringLiteral("token"), QStringLiteral("tok"));
  writeIntegrationConfig(QStringLiteral("gitea"),
                         QJsonObject{
                             {QStringLiteral("connected"), true},
                             {QStringLiteral("host"), gitea.base()},
                             {QStringLiteral("repo"), QStringLiteral("acme/web")},
                         });
  app_->syncProvider(QStringLiteral("gitea"));
  ASSERT_TRUE(heap::testing::waitUntil([&gitea]() {
    return gitea.seen().contains("PATCH /api/v1/repos/acme/web/issues/5");
  })) << "the queued move was never sent";
  EXPECT_TRUE(gitea.lastRequest("PATCH /api/v1/repos/acme/web/issues/5").body.contains("closed"));
  EXPECT_TRUE(heap::testing::waitUntil([this]() {
    const Task* t = task("gitea-5");
    return t && !t->externalMeta.pushQueued && t->externalMeta.unsyncedStatus.isEmpty();
  }));
  EXPECT_EQ(task("gitea-5")->status, QStringLiteral("done")) << "the pull put the card back before the push";
}

TEST_F(IntAudit, QueuedMove_LosesToAMoveMadeInTheTracker) {
  merge({issue("7")});
  edit(QStringLiteral("gh-7"), [](Task& t) {
    t.status = QStringLiteral("prog");
    t.externalMeta.unsyncedStatus = QStringLiteral("prog");
    t.externalMeta.pushQueued = true;
  });
  merge({issue("7", QStringLiteral("closed"))});
  EXPECT_EQ(task("gh-7")->status, QStringLiteral("done"));
  EXPECT_FALSE(task("gh-7")->externalMeta.pushQueued);
}

// ── INT-7: provider reasons in the UI language ──

TEST(IntegrationI18n, KnownReasonsAreTranslated_UnknownOnesPassThrough) {
  using heap::integrations::translateProviderReason;
  const QString jira = QStringLiteral("this issue has no transition to a status mapped to 'blocked' — map one in Settings → Integrations");
  EXPECT_EQ(translateProviderReason(jira, false), jira);
  const QString ru = translateProviderReason(jira, true);
  EXPECT_NE(ru, jira);
  EXPECT_TRUE(ru.contains(QStringLiteral("«blocked»")));
  EXPECT_EQ(translateProviderReason(QStringLiteral("not configured"), true), QStringLiteral("не настроено"));
  EXPECT_EQ(translateProviderReason(QStringLiteral("HTTP 401 — the browser session is no longer valid; sign in again"), true),
            QStringLiteral("HTTP 401 — сессия браузера больше не действительна — войдите снова"));
  // A tracker's own words are not guessed at.
  EXPECT_EQ(translateProviderReason(QStringLiteral("HTTP 422 — Validation Failed"), true), QStringLiteral("HTTP 422 — Validation Failed"));
  EXPECT_EQ(translateProviderReason(QStringLiteral("repo is not configured properly"), true),
            QStringLiteral("repo is not configured properly"));
}

TEST_F(IntAudit, IntegrationToasts_HaveRussian) {
  app_->setLanguage(QStringLiteral("ru"));
  EXPECT_EQ(app_->tr_(QStringLiteral("sync.outOfScope")).left(2), QStringLiteral("%1"));
  EXPECT_TRUE(app_->tr_(QStringLiteral("int.offline")).contains(QStringLiteral("недоступен")));
  app_->setLanguage(QStringLiteral("en"));
}

// ── INT-8: the Jira workflow is consulted on the drop ──

TEST_F(IntAudit, JiraMoveTheWorkflowCannotMake_IsRefusedOnTheDrop) {
  ExternalTask e;
  e.providerId = QStringLiteral("jira");
  e.externalId = QStringLiteral("HT-10");
  e.url = QStringLiteral("https://acme.atlassian.net/browse/HT-10");
  e.title = QStringLiteral("ten");
  e.status = QStringLiteral("To Do");
  e.project = QStringLiteral("HT");
  e.transitionsKnown = true;
  e.transitions = {QStringLiteral("In Progress"), QStringLiteral("Done")};
  app_->mergeExternalTasks(QStringLiteral("jira"), QStringLiteral("jira-"), {e}, true);
  ASSERT_NE(task("jira-HT-10"), nullptr);

  EXPECT_FALSE(app_->canTransitionStatus(QStringLiteral("jira-HT-10"), QStringLiteral("review")));
  EXPECT_FALSE(app_->canTransitionStatus(QStringLiteral("jira-HT-10"), QStringLiteral("blocked")));
  EXPECT_TRUE(app_->canTransitionStatus(QStringLiteral("jira-HT-10"), QStringLiteral("prog")));
  EXPECT_TRUE(app_->canTransitionStatus(QStringLiteral("jira-HT-10"), QStringLiteral("done")));

  app_->moveTask(QStringLiteral("jira-HT-10"), QStringLiteral("review"));
  EXPECT_EQ(task("jira-HT-10")->status, QStringLiteral("todo")) << "the card moved into a column Jira cannot reach";

  // Without reported transitions nothing is second-guessed.
  e.externalId = QStringLiteral("HT-11");
  e.url = QStringLiteral("https://acme.atlassian.net/browse/HT-11");
  e.transitionsKnown = false;
  e.transitions.clear();
  app_->mergeExternalTasks(QStringLiteral("jira"), QStringLiteral("jira-"), {e}, false);
  EXPECT_TRUE(app_->canTransitionStatus(QStringLiteral("jira-HT-11"), QStringLiteral("review")));
}

// ── PLAT-27: the update check ──

TEST(UpdaterCompare, BuildMetadataIsIgnored) {
  using heap::update::isNewerVersion;
  EXPECT_FALSE(isNewerVersion("0.5.2", "v0.5.2+hotfix"));
  EXPECT_FALSE(isNewerVersion("0.5.2+hotfix", "0.5.2"));
  EXPECT_TRUE(isNewerVersion("0.5.2+hotfix", "0.5.3"));
}

TEST(UpdaterCompare, PreReleasesOrder) {
  using heap::update::isNewerVersion;
  EXPECT_TRUE(isNewerVersion("1.0.0-rc1", "1.0.0-rc2"));
  EXPECT_FALSE(isNewerVersion("1.0.0-rc2", "1.0.0-rc1"));
  EXPECT_TRUE(isNewerVersion("1.0.0-rc9", "1.0.0-rc10"));
  EXPECT_TRUE(isNewerVersion("1.0.0-rc.1", "1.0.0-rc.2"));
  EXPECT_TRUE(isNewerVersion("1.0.0-alpha", "1.0.0-beta"));
  EXPECT_TRUE(isNewerVersion("1.0.0-rc2", "1.0.0"));
  EXPECT_FALSE(isNewerVersion("1.0.0-rc1", "1.0.0-rc1"));
}

TEST(UpdaterCompare, FailuresAreClassified) {
  using heap::update::CheckFailure;
  using heap::update::classifyCheckFailure;
  EXPECT_EQ(classifyCheckFailure(403, QNetworkReply::ContentAccessDenied), CheckFailure::RateLimited);
  EXPECT_EQ(classifyCheckFailure(429, QNetworkReply::UnknownContentError), CheckFailure::RateLimited);
  EXPECT_EQ(classifyCheckFailure(0, QNetworkReply::HostNotFoundError), CheckFailure::Offline);
  EXPECT_EQ(classifyCheckFailure(0, QNetworkReply::OperationCanceledError), CheckFailure::Offline);  // transfer timeout
  EXPECT_EQ(classifyCheckFailure(500, QNetworkReply::InternalServerError), CheckFailure::Other);
}

// ── PLAT-28: nothing personal in the issue URL ──

TEST(IssueReport, HomeFolderAndUserNameAreScrubbed) {
  const QString log = QStringLiteral(
      "loaded C:/Users/Fin/AppData/Roaming/heap/state.json\n"
      "backup C:\\Users\\Fin\\AppData\\Roaming\\heap\\backups\n"
      "user fin signed in; Finland stays\n");
  const QString out = heap::diag::scrubPersonalPaths(log, QStringLiteral("C:/Users/Fin"), QStringLiteral("Fin"));
  EXPECT_FALSE(out.contains(QStringLiteral("Users/Fin")));
  EXPECT_FALSE(out.contains(QStringLiteral("Users\\Fin")));
  EXPECT_TRUE(out.contains(QStringLiteral("~/AppData/Roaming/heap/state.json")));
  EXPECT_TRUE(out.contains(QStringLiteral("user <user> signed in")));
  EXPECT_TRUE(out.contains(QStringLiteral("Finland"))) << "a word that merely starts with the name was mangled";
}

TEST(IssueReport, TailKeepsWholeLastLines) {
  QString log;
  for(int i = 0; i < 100; ++i) {
    log += QStringLiteral("line %1\n").arg(i);
  }
  const QString tail = heap::diag::tailLines(log, 5, 1000);
  EXPECT_EQ(tail, QStringLiteral("line 95\nline 96\nline 97\nline 98\nline 99"));
  const QString capped = heap::diag::tailLines(log, 100, 20);
  EXPECT_LE(capped.size(), 20);
  EXPECT_TRUE(capped.startsWith(QStringLiteral("line")));
}

TEST_F(IntAudit, IssueReportBody_IsShortAndCarriesNoHomePath) {
  qWarning() << "audit probe" << QDir::homePath() + QStringLiteral("/secret/file.txt");
  const QString body = app_->issueReportBody();
  EXPECT_FALSE(body.contains(QDir::homePath(), Qt::CaseInsensitive));
  EXPECT_LT(body.size(), 3000);
}

}  // namespace intaudit

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
