#include "integrations/GithubProvider.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

namespace heap::integrations {

QString githubStateForColumn(const QString& column) {
  return column == QStringLiteral("done") ? QStringLiteral("closed") : QStringLiteral("open");
}

QVector<ExternalTask> parseGithubIssues(const QByteArray& json) {
  QVector<ExternalTask> out;
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if(!doc.isArray()) {
    return out;
  }
  const QJsonArray arr = doc.array();
  out.reserve(arr.size());
  for(const auto& v : arr) {
    const QJsonObject o = v.toObject();
    // The issues endpoint also lists pull requests; skip them.
    if(o.contains(QStringLiteral("pull_request"))) {
      continue;
    }
    ExternalTask t;
    t.providerId = QStringLiteral("github");
    t.externalId = QString::number(static_cast<qlonglong>(o.value(QStringLiteral("number")).toDouble()));
    t.url = o.value(QStringLiteral("html_url")).toString();
    t.title = o.value(QStringLiteral("title")).toString();
    t.body = o.value(QStringLiteral("body")).toString();
    t.status = o.value(QStringLiteral("state")).toString();  // "open" | "closed"
    t.updatedAt = QDateTime::fromString(o.value(QStringLiteral("updated_at")).toString(), Qt::ISODate);
    for(const auto& lv : o.value(QStringLiteral("labels")).toArray()) {
      const QString name = lv.toObject().value(QStringLiteral("name")).toString();
      if(name.isEmpty()) {
        continue;
      }
      t.labels.append(name);
      // A "priority: high" style label feeds the priority column via StatusMap.
      if(name.startsWith(QStringLiteral("priority:"), Qt::CaseInsensitive)) {
        t.priority = name.mid(name.indexOf(':') + 1).trimmed();
      }
    }
    out.append(t);
  }
  return out;
}

GithubProvider::GithubProvider(QObject* parent) : IntegrationProvider(parent), m_nam(new QNetworkAccessManager(this)) {
}

GithubProvider::~GithubProvider() = default;

void GithubProvider::setConfig(const QString& repo, const QString& token) {
  m_repo = repo.trimmed();
  m_token = token.trimmed();
}

bool GithubProvider::isConfigured() const {
  return !m_token.isEmpty() && m_repo.contains('/');
}

namespace {

// Build an authenticated GitHub API request for `path` under the repo.
QNetworkRequest apiRequest(const QString& repo, const QString& token, const QString& path) {
  QNetworkRequest req{QUrl(QStringLiteral("https://api.github.com/repos/") + repo + path)};
  req.setRawHeader("Accept", "application/vnd.github+json");
  req.setRawHeader("User-Agent", "heap-sync");
  req.setRawHeader("Authorization", QByteArrayLiteral("token ") + token.toUtf8());
  req.setRawHeader("X-GitHub-Api-Version", "2022-11-28");
  return req;
}

}  // namespace

void GithubProvider::testConnection() {
  if(!isConfigured()) {
    emit connectionTested(false, QStringLiteral("GitHub repo/token not configured"));
    return;
  }
  QNetworkReply* reply = m_nam->get(apiRequest(m_repo, m_token, QString()));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    emit connectionTested(reply->error() == QNetworkReply::NoError, reply->errorString());
  });
}

void GithubProvider::pullTasks() {
  if(!isConfigured()) {
    emit tasksFetched({});
    return;
  }
  QNetworkReply* reply = m_nam->get(apiRequest(m_repo, m_token, QStringLiteral("/issues?state=all&per_page=100")));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      emit tasksFetched({});
      return;
    }
    emit tasksFetched(parseGithubIssues(reply->readAll()));
  });
}

void GithubProvider::pushStatusChange(const QString& externalId, const QString& newStatus) {
  if(!isConfigured() || externalId.isEmpty()) {
    emit taskPushed(externalId, false, QStringLiteral("not configured"));
    return;
  }
  QNetworkRequest req = apiRequest(m_repo, m_token, QStringLiteral("/issues/") + externalId);
  req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
  QJsonObject body;
  body.insert(QStringLiteral("state"), githubStateForColumn(newStatus));
  const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);

  QNetworkReply* reply = m_nam->sendCustomRequest(req, QByteArrayLiteral("PATCH"), payload);
  connect(reply, &QNetworkReply::finished, this, [this, reply, externalId]() {
    reply->deleteLater();
    emit taskPushed(externalId, reply->error() == QNetworkReply::NoError, reply->errorString());
  });
}

}  // namespace heap::integrations
