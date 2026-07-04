#include "integrations/GitlabProvider.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

namespace heap::integrations {

QString gitlabStateEventForColumn(const QString& column) {
  return column == QStringLiteral("done") ? QStringLiteral("close") : QStringLiteral("reopen");
}

QVector<ExternalTask> parseGitlabIssues(const QByteArray& json) {
  QVector<ExternalTask> out;
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if(!doc.isArray()) {
    return out;
  }
  const QJsonArray arr = doc.array();
  out.reserve(arr.size());
  for(const auto& v : arr) {
    const QJsonObject o = v.toObject();
    ExternalTask t;
    t.providerId = QStringLiteral("gitlab");
    t.externalId = QString::number(static_cast<qlonglong>(o.value(QStringLiteral("iid")).toDouble()));
    t.url = o.value(QStringLiteral("web_url")).toString();
    t.title = o.value(QStringLiteral("title")).toString();
    t.body = o.value(QStringLiteral("description")).toString();
    // GitLab state is "opened" | "closed"; StatusMap folds both onto columns.
    t.status = o.value(QStringLiteral("state")).toString();
    t.updatedAt = QDateTime::fromString(o.value(QStringLiteral("updated_at")).toString(), Qt::ISODate);
    // GitLab labels are plain strings. A "priority::high" (scoped) or
    // "priority: high" label feeds the priority column via StatusMap.
    for(const auto& lv : o.value(QStringLiteral("labels")).toArray()) {
      const QString name = lv.toString();
      if(name.isEmpty()) {
        continue;
      }
      t.labels.append(name);
      if(name.startsWith(QStringLiteral("priority"), Qt::CaseInsensitive)) {
        const int sep = name.lastIndexOf(':');
        if(sep >= 0) {
          t.priority = name.mid(sep + 1).trimmed();
        }
      }
    }
    out.append(t);
  }
  return out;
}

GitlabProvider::GitlabProvider(QObject* parent) : IntegrationProvider(parent), m_nam(new QNetworkAccessManager(this)) {
}

GitlabProvider::~GitlabProvider() = default;

void GitlabProvider::setConfig(const QString& host, const QString& project, const QString& token) {
  m_host = host.trimmed();
  while(m_host.endsWith('/')) {
    m_host.chop(1);
  }
  m_project = project.trimmed();
  m_token = token.trimmed();
}

bool GitlabProvider::isConfigured() const {
  return !m_host.isEmpty() && !m_project.isEmpty() && !m_token.isEmpty();
}

namespace {

// A GitLab project path ("group/name") must be URL-encoded to sit in the path;
// a numeric id passes through untouched.
QString encodedProject(const QString& project) {
  if(!project.contains('/')) {
    return project;
  }
  return QString::fromUtf8(QUrl::toPercentEncoding(project));
}

// Build an authenticated GitLab API request for `path` under the project.
QNetworkRequest apiRequest(const QString& host, const QString& project, const QString& token, const QString& path) {
  QNetworkRequest req{QUrl(host + QStringLiteral("/api/v4/projects/") + encodedProject(project) + path)};
  req.setRawHeader("Accept", "application/json");
  req.setRawHeader("User-Agent", "heap-sync");
  req.setRawHeader("PRIVATE-TOKEN", token.toUtf8());
  return req;
}

}  // namespace

void GitlabProvider::testConnection() {
  if(!isConfigured()) {
    emit connectionTested(false, QStringLiteral("GitLab host/project/token not configured"));
    return;
  }
  QNetworkReply* reply = m_nam->get(apiRequest(m_host, m_project, m_token, QString()));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    emit connectionTested(reply->error() == QNetworkReply::NoError, reply->errorString());
  });
}

void GitlabProvider::pullTasks() {
  if(!isConfigured()) {
    emit tasksFetched({});
    return;
  }
  QNetworkReply* reply = m_nam->get(apiRequest(m_host, m_project, m_token, QStringLiteral("/issues?per_page=100&scope=all")));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      emit tasksFetched({});
      return;
    }
    emit tasksFetched(parseGitlabIssues(reply->readAll()));
  });
}

void GitlabProvider::pushStatusChange(const QString& externalId, const QString& newStatus) {
  if(!isConfigured() || externalId.isEmpty()) {
    emit taskPushed(externalId, false, QStringLiteral("not configured"));
    return;
  }
  const QString path = QStringLiteral("/issues/") + externalId + QStringLiteral("?state_event=") + gitlabStateEventForColumn(newStatus);
  const QNetworkRequest req = apiRequest(m_host, m_project, m_token, path);
  QNetworkReply* reply = m_nam->sendCustomRequest(req, QByteArrayLiteral("PUT"));
  connect(reply, &QNetworkReply::finished, this, [this, reply, externalId]() {
    reply->deleteLater();
    emit taskPushed(externalId, reply->error() == QNetworkReply::NoError, reply->errorString());
  });
}

}  // namespace heap::integrations
