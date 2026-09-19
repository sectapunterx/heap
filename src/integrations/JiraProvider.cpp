#include "integrations/JiraProvider.h"
#include "integrations/ReplyError.h"
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

QString normalizeJiraBaseUrl(const QString& raw) {
  QString url = raw.trimmed();
  if(url.isEmpty()) {
    return url;
  }
  // A bare host is the most common paste ("acme.atlassian.net"). Anything
  // without a scheme becomes https — Jira Cloud is https-only anyway, and a
  // scheme-less URL makes QUrl treat the host as a relative path.
  if(!url.contains(QStringLiteral("://"))) {
    url.prepend(QStringLiteral("https://"));
  }
  const QUrl parsed(url);
  // For a Jira Cloud site the path is never part of the API root, and people
  // paste whatever their browser showed — a board, a project, an issue. Keep
  // scheme + host (+ port) and drop the rest. A self-hosted host may well be
  // served under a path prefix, so there only the trailing slashes go.
  if(parsed.isValid() && parsed.host().endsWith(QStringLiteral(".atlassian.net"), Qt::CaseInsensitive)) {
    QUrl root;
    root.setScheme(parsed.scheme());
    root.setHost(parsed.host().toLower());
    if(parsed.port() != -1) {
      root.setPort(parsed.port());
    }
    return root.toString();
  }
  while(url.endsWith('/')) {
    url.chop(1);
  }
  return url;
}

QString defaultJiraJql() {
  // "order by updated DESC" alone is rejected by /search/jql as unbounded, so
  // the default carries a search restriction. Issues assigned to me is also the
  // sane default for a personal todo app, and matches what the GitHub and
  // GitLab cards pull when no repo/project is set.
  return QStringLiteral("assignee = currentUser() ORDER BY updated DESC");
}

JiraProvider::JiraProvider(QObject* parent) : IntegrationProvider(parent), m_nam(new QNetworkAccessManager(this)) {
}

JiraProvider::~JiraProvider() = default;

void JiraProvider::setConfig(const QString& baseUrl, const QString& email, const QString& token, const QString& jql) {
  m_baseUrl = normalizeJiraBaseUrl(baseUrl);
  m_email = email.trimmed();
  m_token = token.trimmed();
  m_jql = jql.trimmed();
  // A new site means the previous gateway decision no longer applies.
  m_apiBase = m_baseUrl;
  m_usingGateway = false;
  m_gatewayTried = false;
}

bool JiraProvider::isConfigured() const {
  return !m_baseUrl.isEmpty() && !m_email.isEmpty() && !m_token.isEmpty();
}

void JiraProvider::sendOnce(const QByteArray& method, const QString& path, const QByteArray& body, const ApiCallback& done) {
  QNetworkRequest req{QUrl(m_apiBase + QStringLiteral("/rest/api/3") + path)};
  req.setRawHeader("Accept", "application/json");
  req.setRawHeader("User-Agent", "heap-sync");
  // Basic base64(email:token) — the same pair works for the site host and for
  // the api.atlassian.com gateway.
  const QByteArray basic = (m_email + QChar(':') + m_token).toUtf8().toBase64();
  req.setRawHeader("Authorization", QByteArrayLiteral("Basic ") + basic);
  if(!body.isEmpty()) {
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
  }

  QNetworkReply* reply = m_nam->sendCustomRequest(req, method, body);
  connect(reply, &QNetworkReply::finished, this, [reply, done]() {
    reply->deleteLater();
    ApiResult r;
    r.status = replyHttpStatus(reply);
    r.body = reply->readAll();
    r.ok = reply->error() == QNetworkReply::NoError;
    if(!r.ok) {
      r.error = describeHttpError(r.status, r.body, reply->errorString());
    }
    done(r);
  });
}

void JiraProvider::resolveCloudId(std::function<void(bool)> done) {
  // Public, unauthenticated endpoint on the site itself: {"cloudId":"…"}.
  QNetworkRequest req{QUrl(m_baseUrl + QStringLiteral("/_edge/tenant_info"))};
  req.setRawHeader("Accept", "application/json");
  req.setRawHeader("User-Agent", "heap-sync");
  QNetworkReply* reply = m_nam->get(req);
  connect(reply, &QNetworkReply::finished, this, [this, reply, done = std::move(done)]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      done(false);
      return;
    }
    const QString cloudId = QJsonDocument::fromJson(reply->readAll()).object().value(QStringLiteral("cloudId")).toString();
    if(cloudId.isEmpty()) {
      done(false);
      return;
    }
    m_apiBase = m_gatewayRoot + QStringLiteral("/ex/jira/") + cloudId;
    m_usingGateway = true;
    done(true);
  });
}

void JiraProvider::send(const QByteArray& method, const QString& path, const QByteArray& body, const ApiCallback& done) {
  sendOnce(method, path, body, [this, method, path, body, done](const ApiResult& first) {
    // Atlassian's scoped API tokens (the default for new tokens) are rejected
    // by the site host and only accepted through the API gateway. A 401 on the
    // site is the only signal we get, so take it as "try the gateway once".
    if(first.status != 401 || m_usingGateway || m_gatewayTried) {
      done(first);
      return;
    }
    m_gatewayTried = true;
    resolveCloudId([this, method, path, body, done, first](bool ok) {
      if(!ok) {
        done(first);  // no cloudId: the original 401 is the real answer
        return;
      }
      sendOnce(method, path, body, done);
    });
  });
}

void JiraProvider::testConnection() {
  if(!isConfigured()) {
    emit connectionTested(false, QStringLiteral("Jira URL/email/token not configured"));
    return;
  }
  send("GET", QStringLiteral("/myself"), {}, [this](const ApiResult& r) {
    emit connectionTested(r.ok, r.error);
  });
}

void JiraProvider::pullTasks() {
  if(!isConfigured()) {
    emit pullFailed(0, QStringLiteral("Jira URL/email/token not configured"));
    return;
  }
  QJsonObject payload;
  payload.insert(QStringLiteral("jql"), m_jql.isEmpty() ? defaultJiraJql() : m_jql);
  payload.insert(QStringLiteral("maxResults"), 100);
  // The /search/jql endpoint requires an explicit `fields` list (omitting it
  // returns only ids); the parser needs exactly these.
  QJsonArray fields;
  for(const auto* f : {"summary", "description", "status", "priority", "labels", "updated"}) {
    fields.append(QLatin1String(f));
  }
  payload.insert(QStringLiteral("fields"), fields);

  // Atlassian retired GET /rest/api/3/search (it answers 410 pointing here);
  // /search/jql is the replacement. POST rather than GET so a long JQL never
  // has to fit in a URL and `fields` can be a real array — the two verbs are
  // otherwise equivalent, including how they judge an unbounded query. It
  // paginates by `nextPageToken` and no longer returns `total`; a single
  // 100-issue page is sufficient for v1.
  const QString site = m_baseUrl;
  send("POST", QStringLiteral("/search/jql"), QJsonDocument(payload).toJson(QJsonDocument::Compact), [this, site](const ApiResult& r) {
    if(!r.ok) {
      emit pullFailed(r.status, r.error);
      return;
    }
    emit tasksFetched(parseJiraIssues(r.body, site));
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
  const QString path = QStringLiteral("/issue/") + externalId + QStringLiteral("/transitions");
  send("GET", path, {}, [this, path, externalId, newStatus](const ApiResult& r) {
    if(!r.ok) {
      emit taskPushed(externalId, false, r.error);
      return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(r.body);
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
    QJsonObject body;
    QJsonObject tr;
    tr.insert(QStringLiteral("id"), transitionId);
    body.insert(QStringLiteral("transition"), tr);
    send("POST", path, QJsonDocument(body).toJson(QJsonDocument::Compact), [this, externalId](const ApiResult& post) {
      emit taskPushed(externalId, post.ok, post.error);
    });
  });
}

}  // namespace heap::integrations
