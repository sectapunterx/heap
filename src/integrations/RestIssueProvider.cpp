#include "integrations/ReplyError.h"
#include "integrations/RestIssueProvider.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>
#include <QUrl>

namespace heap::integrations {

QVector<ExternalTask> parseWithFieldMap(const QByteArray& json, const FieldMap& map, const QString& providerId, const QString& baseUrl) {
  QVector<ExternalTask> out;
  const QJsonDocument doc = QJsonDocument::fromJson(json);

  QJsonArray arr;
  if(map.arrayPointer.isEmpty()) {
    if(!doc.isArray()) {
      return out;
    }
    arr = doc.array();
  } else {
    if(!doc.isObject()) {
      return out;
    }
    arr = valueAtPath(doc.object(), map.arrayPointer).toArray();
  }

  QString site = baseUrl;
  while(site.endsWith('/')) {
    site.chop(1);
  }

  out.reserve(arr.size());
  for(const auto& v : arr) {
    if(!v.isObject()) {
      continue;
    }
    const QJsonObject o = v.toObject();
    ExternalTask t;
    t.providerId = providerId;
    t.externalId = fieldStr(o, map.id);
    t.title = fieldStr(o, map.title);
    t.body = fieldStr(o, map.body);

    if(!map.boolStatusField.isEmpty()) {
      const bool done = valueAtPath(o, map.boolStatusField).toBool();
      t.status = done ? map.boolTrueStatus : map.boolFalseStatus;
    } else {
      t.status = fieldStr(o, map.status);
    }
    t.priority = fieldStr(o, map.priority);

    if(!map.urlTemplate.isEmpty()) {
      QString url = map.urlTemplate;
      url.replace(QStringLiteral("{baseUrl}"), site);
      url.replace(QStringLiteral("{id}"), t.externalId);
      t.url = url;
    } else {
      t.url = fieldStr(o, map.url);
    }

    t.updatedAt = parseTrackerTimestamp(valueAtPath(o, map.updatedAt));
    t.createdAt = parseTrackerTimestamp(valueAtPath(o, map.createdAt));
    t.dueAt = parseTrackerTimestamp(valueAtPath(o, map.dueAt), &t.dueHasTime);
    // A provider that answers the question separately (ClickUp's due_date_time)
    // overrules what the value's own shape suggested.
    if(!map.dueHasTimeField.isEmpty() && t.dueAt.isValid()) {
      t.dueHasTime = valueAtPath(o, map.dueHasTimeField).toBool();
    }
    t.assignee = fieldStr(o, map.assignee);
    t.author = fieldStr(o, map.author);
    t.issueType = fieldStr(o, map.issueType);
    t.project = sanitizeProject(fieldStr(o, map.project));
    t.milestone = fieldStr(o, map.milestone);
    if(!map.commentCount.isEmpty()) {
      const QJsonValue n = valueAtPath(o, map.commentCount);
      if(n.isDouble()) {
        t.commentCount = n.toInt(-1);
      }
    }

    if(!map.labels.isEmpty()) {
      const QJsonArray labels = valueAtPath(o, map.labels).toArray();
      for(const auto& lv : labels) {
        QString name;
        QString color;
        if(map.labelNameKey.isEmpty()) {
          name = lv.toString();
        } else if(lv.isObject()) {
          const QJsonObject lo = lv.toObject();
          name = lo.value(map.labelNameKey).toString();
          if(!map.labelColorKey.isEmpty()) {
            color = normalizeHexColor(lo.value(map.labelColorKey).toString());
          }
        }
        if(!name.isEmpty()) {
          t.labels.append(name);
          if(!color.isEmpty()) {
            t.labelColors.insert(name, color);
          }
        }
      }
    }
    out.append(t);
  }
  return out;
}

QVector<ExternalComment> parseCommentsWithMap(const QByteArray& json, const CommentMap& map) {
  QVector<ExternalComment> out;
  const QJsonDocument doc = QJsonDocument::fromJson(json);

  QJsonArray arr;
  if(map.arrayPointer.isEmpty()) {
    if(!doc.isArray()) {
      return out;
    }
    arr = doc.array();
  } else {
    if(!doc.isObject()) {
      return out;
    }
    arr = valueAtPath(doc.object(), map.arrayPointer).toArray();
  }

  out.reserve(arr.size());
  for(const auto& v : arr) {
    if(!v.isObject()) {
      continue;
    }
    const QJsonObject o = v.toObject();
    // GitLab returns "changed the description" alongside real comments.
    if(!map.skipIfTrue.isEmpty() && valueAtPath(o, map.skipIfTrue).toBool()) {
      continue;
    }
    ExternalComment c;
    c.author = fieldStr(o, map.author);
    c.body = fieldStr(o, map.body);
    c.createdAt = parseTrackerTimestamp(valueAtPath(o, map.createdAt));
    c.url = fieldStr(o, map.url);
    if(c.body.isEmpty()) {
      continue;
    }
    out.append(c);
  }
  return out;
}

RestIssueProvider::RestIssueProvider(ProviderDescriptor desc, QObject* parent) :
    IntegrationProvider(parent), m_desc(std::move(desc)), m_nam(new QNetworkAccessManager(this)) {
}

RestIssueProvider::~RestIssueProvider() = default;

void RestIssueProvider::setConfig(const QVariantMap& cfg) {
  m_cfg.clear();
  for(auto it = cfg.constBegin(); it != cfg.constEnd(); ++it) {
    m_cfg.insert(it.key(), it.value().toString().trimmed());
  }
}

bool RestIssueProvider::isConfigured() const {
  for(const QString& key : m_desc.requiredKeys) {
    if(m_cfg.value(key).toString().isEmpty()) {
      return false;
    }
  }
  return true;
}

QString RestIssueProvider::expand(const QString& tmpl, const QVariantMap& extra) const {
  QString out;
  out.reserve(tmpl.size());
  int i = 0;
  while(i < tmpl.size()) {
    const QChar c = tmpl.at(i);
    if(c != QChar('{')) {
      out += c;
      ++i;
      continue;
    }
    const int close = tmpl.indexOf(QChar('}'), i);
    if(close < 0) {
      out += tmpl.mid(i);
      break;
    }
    QString token = tmpl.mid(i + 1, close - i - 1);
    bool enc = false;
    if(token.endsWith(QStringLiteral(":enc"))) {
      enc = true;
      token.chop(4);
    }
    QString value = extra.contains(token) ? extra.value(token).toString() : m_cfg.value(token).toString();
    if(token == QStringLiteral("host") || token == QStringLiteral("baseUrl")) {
      while(value.endsWith('/')) {
        value.chop(1);
      }
    }
    if(enc) {
      value = QString::fromUtf8(QUrl::toPercentEncoding(value));
    }
    out += value;
    i = close + 1;
  }
  return out;
}

bool RestIssueProvider::inSelfScope() const {
  return !m_desc.selfListPathTemplate.isEmpty() && !m_desc.scopeKey.isEmpty() && m_cfg.value(m_desc.scopeKey).toString().isEmpty();
}

QString RestIssueProvider::listPath() const {
  return inSelfScope() ? m_desc.selfListPathTemplate : m_desc.listPathTemplate;
}

QString RestIssueProvider::resolvedBaseUrl() const {
  QString base = expand(m_desc.baseUrlTemplate);
  if(base.isEmpty()) {
    base = m_desc.baseUrlFallback;
  }
  while(base.endsWith('/')) {
    base.chop(1);
  }
  return base;
}

QNetworkRequest RestIssueProvider::buildRequest(const QString& url) const {
  QNetworkRequest req{QUrl(url)};
  // Qt would follow a redirect to another host and carry the credentials
  // with it; keep every authenticated call on the origin it was aimed at.
  req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::SameOriginRedirectPolicy);
  req.setRawHeader("User-Agent", "heap-sync");
  for(const auto& h : m_desc.auth.extraHeaders) {
    req.setRawHeader(h.first, h.second);
  }
  const QByteArray token = m_cfg.value(m_desc.tokenKey).toString().toUtf8();
  // A token obtained via browser OAuth is a bearer token regardless of the
  // provider's default PAT header (e.g. GitLab uses PRIVATE-TOKEN for PATs but
  // Authorization: Bearer for OAuth access tokens).
  if(m_cfg.value(QStringLiteral("authMode")).toString() == QStringLiteral("oauth")) {
    req.setRawHeader("Authorization", QByteArrayLiteral("Bearer ") + token);
    return req;
  }
  switch(m_desc.auth.kind) {
    case AuthKind::HeaderToken:
      req.setRawHeader(m_desc.auth.headerName, m_desc.auth.tokenPrefix + token);
      break;
    case AuthKind::CustomHeader:
      req.setRawHeader(m_desc.auth.headerName, token);
      break;
  }
  return req;
}

void RestIssueProvider::testConnection() {
  if(!isConfigured()) {
    emit connectionTested(false, m_desc.displayName + QStringLiteral(" is not fully configured"));
    return;
  }
  const QString url = resolvedBaseUrl() + expand(listPath());
  QNetworkReply* reply = m_nam->get(buildRequest(url));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    const bool ok = reply->error() == QNetworkReply::NoError;
    emit connectionTested(ok, ok ? QString() : describeReplyError(reply));
  });
}

void RestIssueProvider::pullTasks() {
  if(!isConfigured()) {
    emit pullFailed(0, m_desc.displayName + QStringLiteral(" is not fully configured"));
    return;
  }
  if(m_pull.active) {
    // The auto-sync timer and the Sync-now button can both land while a walk is
    // in flight. Starting a second one would interleave two page sequences into
    // one accumulator and emit twice.
    return;
  }
  m_pull = Pull{};
  m_pull.active = true;
  m_pull.base = resolvedBaseUrl();
  m_pull.url = QUrl(m_pull.base + expand(listPath()));
  // Which endpoint this pull went to decides whether the issue numbers coming
  // back are unique on their own. Captured now, not when a reply lands, so a
  // repo configured mid-flight cannot mislabel the answer.
  m_pull.crossProject = inSelfScope();
  m_pull.offset = m_desc.paging.firstOffset;
  fetchPage();
}

void RestIssueProvider::fetchPage() {
  QNetworkReply* reply = m_nam->get(buildRequest(m_pull.url.toString()));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      const int status = replyHttpStatus(reply);
      // 429 is the server asking for a pause, and 5xx is it having a bad
      // moment. Both are worth waiting out; everything else (401, 404, a bad
      // query) will fail again identically, so retrying only delays the toast.
      const bool worthRetrying = status == 429 || (status >= 500 && status < 600);
      if(worthRetrying && m_pull.attempt < m_desc.retry.maxRetries) {
        // describeReplyError() consumes the body, so read the header first.
        const QByteArray after = reply->rawHeader("Retry-After");
        const int asked = retryAfterMs(after, QDateTime::currentDateTime());
        const int backoff = m_desc.retry.baseDelayMs * (1 << m_pull.attempt);
        const int waitMs = qBound(0, asked > 0 ? asked : backoff, m_desc.retry.maxDelayMs);
        ++m_pull.attempt;
        QTimer::singleShot(waitMs, this, [this]() {
          if(m_pull.active) {
            fetchPage();
          }
        });
        return;
      }
      const QString error = describeReplyError(reply);
      if(m_pull.page > 0) {
        // Pages already in hand are real issues; throwing them away because the
        // tail failed would be a worse answer than a short one. Report the
        // truncation separately so it is not silent.
        finishPull(error);
        return;
      }
      m_pull.active = false;
      emit pullFailed(status, error);
      return;
    }
    m_pull.attempt = 0;
    onPage(reply->readAll(), reply->rawHeader("Link"));
  });
}

void RestIssueProvider::onPage(const QByteArray& body, const QByteArray& linkHeader) {
  QVector<ExternalTask> tasks =
      m_desc.parser ? m_desc.parser(body, m_pull.base) : parseWithFieldMap(body, m_desc.fields, m_desc.id, m_pull.base);
  const int count = static_cast<int>(tasks.size());
  if(m_pull.crossProject) {
    for(ExternalTask& t : tasks) {
      t.crossProject = true;
    }
  }
  m_pull.tasks += tasks;
  ++m_pull.page;

  if(m_pull.page >= qMax(1, m_desc.paging.maxPages)) {
    // The cap is not an error — it is the promise that one sync is bounded —
    // but a walk that hits it did leave issues behind, so say so.
    finishPull(m_pull.page > 1 || m_desc.paging.style != PageStyle::None
                   ? QStringLiteral("stopped at the %1-page limit").arg(m_desc.paging.maxPages)
                   : QString());
    return;
  }
  const QUrl next = nextPageUrl(body, linkHeader, count);
  if(!next.isValid() || next.isEmpty()) {
    finishPull(QString());
    return;
  }
  m_pull.url = next;
  fetchPage();
}

QUrl RestIssueProvider::nextPageUrl(const QByteArray& body, const QByteArray& linkHeader, int lastCount) {
  switch(m_desc.paging.style) {
    case PageStyle::None:
      return {};
    case PageStyle::LinkHeader: {
      const QString next = nextLinkFromHeader(linkHeader);
      if(next.isEmpty()) {
        return {};
      }
      const QUrl url(next);
      // The link is server-supplied. Following it to another host would carry
      // the token there, which is exactly what SameOriginRedirectPolicy is set
      // to prevent on redirects.
      if(!url.isValid() || url.host() != m_pull.url.host() || url.scheme() != m_pull.url.scheme()) {
        return {};
      }
      return url;
    }
    case PageStyle::BodyNext: {
      const QJsonObject root = QJsonDocument::fromJson(body).object();
      const QString leaf = fieldStr(root, m_desc.paging.bodyPath);
      if(leaf.isEmpty()) {
        return {};
      }
      if(m_desc.paging.cursorParam.isEmpty()) {
        const QUrl url(leaf);
        if(!url.isValid() || url.host() != m_pull.url.host() || url.scheme() != m_pull.url.scheme()) {
          return {};
        }
        return url;
      }
      return withQueryParam(m_pull.url, m_desc.paging.cursorParam, leaf);
    }
    case PageStyle::Offset: {
      // A page shorter than the size we asked for is the last one. An endpoint
      // that ignores the parameter therefore stops after one page rather than
      // looping on the same content.
      const int size = m_desc.paging.pageSize;
      if(size <= 0 || lastCount < size || m_desc.paging.offsetParam.isEmpty()) {
        return {};
      }
      const int step = m_desc.paging.offsetStep > 0 ? m_desc.paging.offsetStep : size;
      m_pull.offset += step;
      return withQueryParam(m_pull.url, m_desc.paging.offsetParam, QString::number(m_pull.offset));
    }
  }
  return {};
}

void RestIssueProvider::finishPull(const QString& truncatedReason) {
  const QVector<ExternalTask> tasks = m_pull.tasks;
  const int pages = m_pull.page;
  m_pull.active = false;
  m_pull.tasks.clear();
  // tasksFetched first: the issues we did get should land whatever happened to
  // the rest, and AppController's toast for the merge is the useful one.
  emit tasksFetched(tasks);
  if(!truncatedReason.isEmpty()) {
    // Status 0 deliberately: a mid-walk 401 must not send AppController into
    // its refresh-and-resync path, which would re-pull page 1 forever. The next
    // sync's first page will fail the same way and refresh then.
    emit pullFailed(0, QStringLiteral("%1: only %2 page(s) — %3").arg(m_desc.displayName).arg(pages).arg(truncatedReason));
  }
}

void RestIssueProvider::fetchComments(const QString& externalId, const QString& project) {
  if(m_desc.commentsPathTemplate.isEmpty()) {
    emit commentsFetched(externalId, {}, QStringLiteral("unsupported"));
    return;
  }
  if(!isConfigured() || externalId.isEmpty()) {
    emit commentsFetched(externalId, {}, QStringLiteral("not configured"));
    return;
  }
  QVariantMap extra;
  extra.insert(QStringLiteral("externalId"), externalId);
  // The issue's own repo, which in a cross-project pull is not the configured
  // one. expand() prefers `extra` over the config, so this simply wins.
  if(!project.isEmpty() && !m_desc.scopeKey.isEmpty()) {
    extra.insert(m_desc.scopeKey, project);
  }
  const QString url = resolvedBaseUrl() + expand(m_desc.commentsPathTemplate, extra);

  QNetworkReply* reply = m_nam->get(buildRequest(url));
  connect(reply, &QNetworkReply::finished, this, [this, reply, externalId]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      emit commentsFetched(externalId, {}, describeReplyError(reply));
      return;
    }
    QVector<ExternalComment> comments = parseCommentsWithMap(reply->readAll(), m_desc.comments);
    // GitHub and Gitea have no sort parameter and answer oldest-first.
    if(m_desc.comments.newestLast) {
      std::reverse(comments.begin(), comments.end());
    }
    emit commentsFetched(externalId, comments, QString());
  });
}

void RestIssueProvider::pushStatusChange(const QString& externalId, const QString& newStatus) {
  if(m_desc.pushPathTemplate.isEmpty() || inSelfScope()) {
    // Pull-only provider (or a "my issues" pull with no repo to write back to):
    // report success without touching the remote so moving a linked task never
    // spams the log with "push failed".
    emit taskPushed(externalId, true, QStringLiteral("pull-only"));
    return;
  }
  if(!isConfigured() || externalId.isEmpty()) {
    emit taskPushed(externalId, false, QStringLiteral("not configured"));
    return;
  }
  const QString state = m_desc.pushMap ? m_desc.pushMap(newStatus) : newStatus;
  QVariantMap extra;
  extra.insert(QStringLiteral("externalId"), externalId);
  extra.insert(QStringLiteral("state"), state);
  const QString url = expand(m_desc.baseUrlTemplate) + expand(m_desc.pushPathTemplate, extra);

  QNetworkRequest req = buildRequest(url);
  QByteArray body;
  if(!m_desc.pushBodyTemplate.isEmpty()) {
    body = m_desc.pushBodyTemplate;
    body.replace("{state}", state.toUtf8());
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
  }
  QNetworkReply* reply = m_nam->sendCustomRequest(req, m_desc.pushMethod.toUtf8(), body);
  connect(reply, &QNetworkReply::finished, this, [this, reply, externalId]() {
    reply->deleteLater();
    const bool ok = reply->error() == QNetworkReply::NoError;
    emit taskPushed(externalId, ok, ok ? QString() : describeReplyError(reply));
  });
}

}  // namespace heap::integrations
