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
  // without a scheme becomes https — a scheme-less URL makes QUrl treat the
  // host as a relative path.
  if(!url.contains(QStringLiteral("://"))) {
    url.prepend(QStringLiteral("https://"));
  }
  const QUrl parsed(url);
  if(!parsed.isValid() || parsed.host().isEmpty()) {
    while(url.endsWith('/')) {
      url.chop(1);
    }
    return url;
  }

  QUrl root;
  root.setScheme(parsed.scheme());
  root.setHost(parsed.host().toLower());
  if(parsed.port() != -1) {
    root.setPort(parsed.port());
  }

  // On Jira Cloud the API root is always the bare site, so everything after the
  // host goes.
  if(parsed.host().endsWith(QStringLiteral(".atlassian.net"), Qt::CaseInsensitive)) {
    return root.toString();
  }

  // A self-hosted Jira may genuinely live under a prefix ("https://host/jira"),
  // so the path cannot simply be dropped. But what people paste is the URL
  // their browser was showing — a ticket, a board, a project — and keeping that
  // turned every API call into "<host>/browse/TEL-1/rest/api/…", which comes
  // back 401 or 404 with nothing pointing at the real mistake.
  //
  // Cut at the first segment that can only be a UI route, and keep whatever
  // came before it as the deployment prefix. "jira" and "software" are
  // deliberately not in this list: as a first segment they are far more often
  // the prefix itself ("/jira/browse/X-1" means prefix "/jira").
  static const QStringList kUiRoutes = {
      QStringLiteral("browse"),
      QStringLiteral("projects"),
      QStringLiteral("issues"),
      QStringLiteral("secure"),
      QStringLiteral("plugins"),
      QStringLiteral("rest"),
  };
  QStringList prefix;
  const QStringList segments = parsed.path().split(QLatin1Char('/'), Qt::SkipEmptyParts);
  for(const QString& segment : segments) {
    if(kUiRoutes.contains(segment, Qt::CaseInsensitive)) {
      break;
    }
    prefix.append(segment);
  }
  if(!prefix.isEmpty()) {
    root.setPath(QLatin1Char('/') + prefix.join(QLatin1Char('/')));
  }
  return root.toString();
}

QString defaultJiraJql() {
  // "order by updated DESC" alone is rejected by /search/jql as unbounded, so
  // the default carries a search restriction. Issues assigned to me is also the
  // sane default for a personal todo app, and matches what the GitHub and
  // GitLab cards pull when no repo/project is set.
  return QStringLiteral("assignee = currentUser() ORDER BY updated DESC");
}

JiraSite pickJiraSite(const QByteArray& accessibleResourcesJson, const QString& preferredUrl) {
  const QJsonArray sites = QJsonDocument::fromJson(accessibleResourcesJson).array();
  if(sites.isEmpty()) {
    return {};
  }
  // A token can be granted several sites. If the card already names one, keep
  // it — switching sites silently would repoint every synced issue.
  const QString wanted = normalizeJiraBaseUrl(preferredUrl);
  if(!wanted.isEmpty()) {
    for(const auto& v : sites) {
      const QJsonObject site = v.toObject();
      if(normalizeJiraBaseUrl(site.value(QStringLiteral("url")).toString()) == wanted) {
        return {site.value(QStringLiteral("id")).toString(), site.value(QStringLiteral("url")).toString()};
      }
    }
  }
  const QJsonObject first = sites.first().toObject();
  return {first.value(QStringLiteral("id")).toString(), first.value(QStringLiteral("url")).toString()};
}

JiraProvider::JiraProvider(QObject* parent) : IntegrationProvider(parent), m_nam(new QNetworkAccessManager(this)) {
}

JiraProvider::~JiraProvider() = default;

void JiraProvider::setConfig(const QString& baseUrl, const QString& email, const QString& token, const QString& jql) {
  m_baseUrl = normalizeJiraBaseUrl(baseUrl);
  m_email = email.trimmed();
  m_token = token.trimmed();
  m_jql = jql.trimmed();
  m_oauth = false;
  // A new site means the previous gateway decision no longer applies.
  m_apiBase = m_baseUrl;
  m_usingGateway = false;
  m_gatewayTried = false;
}

void JiraProvider::setOAuthConfig(const QString& cloudId, const QString& siteUrl, const QString& token, const QString& jql) {
  m_baseUrl = normalizeJiraBaseUrl(siteUrl);
  m_email.clear();
  m_token = token.trimmed();
  m_jql = jql.trimmed();
  m_oauth = true;
  // A 3LO token is only accepted by the gateway, never by the site host, so
  // there is nothing to discover here and no 401 fallback to run. Without a
  // cloudId there is no API base at all — stay unconfigured rather than send
  // every call to a truncated /ex/jira/ path.
  const QString id = cloudId.trimmed();
  m_usingGateway = !id.isEmpty();
  m_apiBase = m_usingGateway ? m_gatewayRoot + QStringLiteral("/ex/jira/") + id : QString();
  m_gatewayTried = true;
}

bool JiraProvider::isConfigured() const {
  if(m_token.isEmpty()) {
    return false;
  }
  // OAuth needs no email, and no site URL either — browse links degrade to the
  // issue key, but the API base is already the gateway.
  return m_oauth ? m_usingGateway : (!m_baseUrl.isEmpty() && !m_email.isEmpty());
}

void JiraProvider::sendOnce(const QByteArray& method, const QString& path, const QByteArray& body, const ApiCallback& done) {
  QNetworkRequest req{QUrl(m_apiBase + QStringLiteral("/rest/api/3") + path)};
  req.setRawHeader("Accept", "application/json");
  req.setRawHeader("User-Agent", "heap-sync");
  if(m_oauth) {
    // A 3LO access token is a Bearer credential; there is no email to pair it
    // with. Only the gateway accepts it.
    req.setRawHeader("Authorization", QByteArrayLiteral("Bearer ") + m_token.toUtf8());
  } else {
    // Basic base64(email:token) — the same pair works for the site host and for
    // the api.atlassian.com gateway.
    const QByteArray basic = (m_email + QChar(':') + m_token).toUtf8().toBase64();
    req.setRawHeader("Authorization", QByteArrayLiteral("Basic ") + basic);
  }
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
      done(explainAuthFailure(first, /*cloudIdResolved=*/m_usingGateway));
      return;
    }
    m_gatewayTried = true;
    resolveCloudId([this, method, path, body, done, first](bool ok) {
      if(!ok) {
        // No cloudId either: the site is not Jira Cloud, or it is unreachable.
        done(explainAuthFailure(first, /*cloudIdResolved=*/false));
        return;
      }
      sendOnce(method, path, body, [this, done](const ApiResult& viaGateway) {
        done(explainAuthFailure(viaGateway, /*cloudIdResolved=*/true));
      });
    });
  });
}

JiraProvider::ApiResult JiraProvider::explainAuthFailure(const ApiResult& result, bool cloudIdResolved) const {
  if(result.ok || result.status != 401) {
    return result;
  }
  ApiResult out = result;
  if(m_oauth) {
    out.error = QStringLiteral("HTTP 401 — the browser session is no longer valid; sign in again");
    return out;
  }

  // Jira sometimes says exactly what is wrong ("Basic auth with password is not
  // allowed"), and that is worth more than anything generic — keep it and add
  // what to do. When it says nothing useful, Qt's "Host requires
  // authentication" is what would otherwise reach the user, so the guidance is
  // all there is.
  QString advice = QStringLiteral("use an API token from id.atlassian.com, with the email of that same Atlassian account");
  if(!cloudIdResolved) {
    // /_edge/tenant_info is Cloud-only, so a site that refused us and has no
    // cloudId is usually not Cloud at all — easy to miss, hard to guess.
    advice += QStringLiteral("; if this is Jira Server or Data Center, it is not supported");
  }
  const QString fromJira = detail::messageFromBody(result.body);
  out.error = fromJira.isEmpty() ? QStringLiteral("HTTP 401 — ") + advice
                                 : QStringLiteral("HTTP 401 — %1 · %2").arg(detail::clampMessage(fromJira), advice);
  return out;
}

void JiraProvider::testConnection() {
  if(!isConfigured()) {
    emit connectionTested(false,
                          m_oauth ? QStringLiteral("Jira browser sign-in is incomplete — sign in again")
                                  : QStringLiteral("Jira URL/email/token not configured"));
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
