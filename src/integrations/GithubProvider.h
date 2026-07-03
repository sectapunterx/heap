#pragma once

#include "integrations/IntegrationProvider.h"
#include "integrations/IntegrationTypes.h"

#include <QByteArray>
#include <QString>
#include <QVector>

class QNetworkAccessManager;

namespace heap::integrations {

// Parse a GitHub "list issues" JSON array into ExternalTasks. Pull requests
// (issues carrying a "pull_request" node) are skipped — the issues endpoint
// returns both. Pure, no network — unit-tested with canned JSON.
QVector<ExternalTask> parseGithubIssues(const QByteArray& json);

// Push-direction inverse of StatusMap: a heap column → the GitHub issue state.
// Only "done" closes an issue; every other column (re)opens it.
QString githubStateForColumn(const QString& column);

// Concrete IntegrationProvider backed by the GitHub REST API (HEAP-74). Uses a
// personal-access token (PAT) stored locally — no server, no OAuth for v1.
// Mirrors the QNetworkAccessManager pattern of heap::update::Updater.
class GithubProvider : public IntegrationProvider {
  Q_OBJECT

 public:
  explicit GithubProvider(QObject* parent = nullptr);
  ~GithubProvider() override;

  // Configure from the Settings → Integrations GitHub card. `repo` is an
  // "org/name" slug; `token` a PAT. Both required before any request runs.
  void setConfig(const QString& repo, const QString& token);
  bool isConfigured() const;

  QString id() const override {
    return QStringLiteral("github");
  }

  QString displayName() const override {
    return QStringLiteral("GitHub");
  }

  void testConnection() override;
  void pullTasks() override;
  void pushStatusChange(const QString& externalId, const QString& newStatus) override;

 private:
  QNetworkAccessManager* m_nam = nullptr;
  QString m_repo;   // "org/name"
  QString m_token;  // PAT
};

}  // namespace heap::integrations
