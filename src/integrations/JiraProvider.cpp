#include "integrations/JiraProvider.h"
#include "integrations/StatusMap.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>

namespace heap::integrations {

namespace {

// Recursively collect every "text" leaf of an ADF node, separating block-level
// nodes with newlines so paragraphs stay readable.
void walkAdf(const QJsonValue& node, QString& out) {
  if(node.isString()) {
    out += node.toString();
    return;
  }
  if(node.isArray()) {
    for(const auto& child : node.toArray()) {
      walkAdf(child, out);
    }
    return;
  }
  if(!node.isObject()) {
    return;
  }
  const QJsonObject o = node.toObject();
  const QString type = o.value(QStringLiteral("type")).toString();
  if(o.contains(QStringLiteral("text"))) {
    out += o.value(QStringLiteral("text")).toString();
  }
  if(o.contains(QStringLiteral("content"))) {
    walkAdf(o.value(QStringLiteral("content")), out);
  }
  // Block separators keep list items / paragraphs on their own lines.
  if(type == QStringLiteral("paragraph") || type == QStringLiteral("listItem") || type == QStringLiteral("heading")) {
    out += QChar('\n');
  }
}

QString adfValueToText(const QJsonValue& description) {
  if(description.isString()) {
    return description.toString();
  }
  QString out;
  walkAdf(description, out);
  return out.trimmed();
}

}  // namespace

QString jiraAdfToPlainText(const QByteArray& adfJson) {
  const QJsonDocument doc = QJsonDocument::fromJson(adfJson);
  if(doc.isObject()) {
    return adfValueToText(doc.object());
  }
  if(doc.isArray()) {
    return adfValueToText(doc.array());
  }
  return QString();
}

QVector<ExternalTask> parseJiraIssues(const QByteArray& json, const QString& baseUrl) {
  QVector<ExternalTask> out;
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if(!doc.isObject()) {
    return out;
  }
  QString site = baseUrl;
  while(site.endsWith('/')) {
    site.chop(1);
  }
  const QJsonArray issues = doc.object().value(QStringLiteral("issues")).toArray();
  out.reserve(issues.size());
  for(const auto& v : issues) {
    const QJsonObject o = v.toObject();
    const QJsonObject fields = o.value(QStringLiteral("fields")).toObject();
    ExternalTask t;
    t.providerId = QStringLiteral("jira");
    t.externalId = o.value(QStringLiteral("key")).toString();  // e.g. "PROJ-123"
    t.url = site + QStringLiteral("/browse/") + t.externalId;
    t.title = fields.value(QStringLiteral("summary")).toString();
    t.body = adfValueToText(fields.value(QStringLiteral("description")));
    t.status = fields.value(QStringLiteral("status")).toObject().value(QStringLiteral("name")).toString();
    t.priority = fields.value(QStringLiteral("priority")).toObject().value(QStringLiteral("name")).toString();
    for(const auto& lv : fields.value(QStringLiteral("labels")).toArray()) {
      const QString name = lv.toString();
      if(!name.isEmpty()) {
        t.labels.append(name);
      }
    }
    t.updatedAt = QDateTime::fromString(fields.value(QStringLiteral("updated")).toString(), Qt::ISODate);
    out.append(t);
  }
  return out;
}

JiraProvider::JiraProvider(QObject* parent) : IntegrationProvider(parent), m_nam(new QNetworkAccessManager(this)) {
}

JiraProvider::~JiraProvider() = default;

void JiraProvider::setConfig(const QString& baseUrl, const QString& email, const QString& token, const QString& jql) {
  m_baseUrl = baseUrl.trimmed();
  while(m_baseUrl.endsWith('/')) {
    m_baseUrl.chop(1);
  }
  m_email = email.trimmed();
  m_token = token.trimmed();
  m_jql = jql.trimmed();
}

bool JiraProvider::isConfigured() const {
  return !m_baseUrl.isEmpty() && !m_email.isEmpty() && !m_token.isEmpty();
}

namespace {

// Build an authenticated Jira Cloud request. Auth is Basic base64(email:token).
QNetworkRequest apiRequest(const QString& baseUrl, const QString& email, const QString& token, const QString& path) {
  QNetworkRequest req{QUrl(baseUrl + QStringLiteral("/rest/api/3") + path)};
  req.setRawHeader("Accept", "application/json");
  req.setRawHeader("User-Agent", "heap-sync");
  const QByteArray basic = (email + QChar(':') + token).toUtf8().toBase64();
  req.setRawHeader("Authorization", QByteArrayLiteral("Basic ") + basic);
  return req;
}

}  // namespace

void JiraProvider::testConnection() {
  if(!isConfigured()) {
    emit connectionTested(false, QStringLiteral("Jira URL/email/token not configured"));
    return;
  }
  QNetworkReply* reply = m_nam->get(apiRequest(m_baseUrl, m_email, m_token, QStringLiteral("/myself")));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    emit connectionTested(reply->error() == QNetworkReply::NoError, reply->errorString());
  });
}

void JiraProvider::pullTasks() {
  if(!isConfigured()) {
    emit tasksFetched({});
    return;
  }
  QUrlQuery q;
  q.addQueryItem(QStringLiteral("jql"), m_jql.isEmpty() ? QStringLiteral("order by updated DESC") : m_jql);
  q.addQueryItem(QStringLiteral("maxResults"), QStringLiteral("100"));
  // The new /search/jql endpoint requires an explicit `fields` list (omitting it
  // returns only ids); the parser needs exactly these.
  q.addQueryItem(QStringLiteral("fields"), QStringLiteral("summary,description,status,priority,labels,updated"));
  // Atlassian retired GET /rest/api/3/search (2025); /search/jql is the
  // replacement. It paginates by `nextPageToken` and no longer returns `total`;
  // a single 100-issue page is sufficient for v1.
  const QString path = QStringLiteral("/search/jql?") + q.query(QUrl::FullyEncoded);
  const QString site = m_baseUrl;
  QNetworkReply* reply = m_nam->get(apiRequest(m_baseUrl, m_email, m_token, path));
  connect(reply, &QNetworkReply::finished, this, [this, reply, site]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      emit tasksFetched({});
      return;
    }
    emit tasksFetched(parseJiraIssues(reply->readAll(), site));
  });
}

void JiraProvider::pushStatusChange(const QString& externalId, const QString& newStatus) {
  if(!isConfigured() || externalId.isEmpty()) {
    emit taskPushed(externalId, false, QStringLiteral("not configured"));
    return;
  }
  // Jira has no direct "set status" — you POST one of the issue's available
  // workflow transitions. Fetch them, pick the one whose target status maps to
  // the requested heap column, then execute it.
  QNetworkReply* getReply =
      m_nam->get(apiRequest(m_baseUrl, m_email, m_token, QStringLiteral("/issue/") + externalId + QStringLiteral("/transitions")));
  connect(getReply, &QNetworkReply::finished, this, [this, getReply, externalId, newStatus]() {
    getReply->deleteLater();
    if(getReply->error() != QNetworkReply::NoError) {
      emit taskPushed(externalId, false, getReply->errorString());
      return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(getReply->readAll());
    const QJsonArray transitions = doc.object().value(QStringLiteral("transitions")).toArray();
    QString transitionId;
    for(const auto& tv : transitions) {
      const QJsonObject to = tv.toObject().value(QStringLiteral("to")).toObject();
      const QString targetColumn = StatusMap::column(to.value(QStringLiteral("name")).toString(), {}, QString());
      if(targetColumn == newStatus) {
        transitionId = tv.toObject().value(QStringLiteral("id")).toString();
        break;
      }
    }
    if(transitionId.isEmpty()) {
      emit taskPushed(externalId, false, QStringLiteral("no matching transition for column '%1'").arg(newStatus));
      return;
    }
    QNetworkRequest req = apiRequest(m_baseUrl, m_email, m_token, QStringLiteral("/issue/") + externalId + QStringLiteral("/transitions"));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QJsonObject body;
    QJsonObject tr;
    tr.insert(QStringLiteral("id"), transitionId);
    body.insert(QStringLiteral("transition"), tr);
    const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    QNetworkReply* postReply = m_nam->post(req, payload);
    connect(postReply, &QNetworkReply::finished, this, [this, postReply, externalId]() {
      postReply->deleteLater();
      emit taskPushed(externalId, postReply->error() == QNetworkReply::NoError, postReply->errorString());
    });
  });
}

}  // namespace heap::integrations
