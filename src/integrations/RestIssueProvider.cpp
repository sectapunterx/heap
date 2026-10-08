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
    if(c.url.isEmpty() && !map.anchorId.isEmpty()) {
      const QJsonValue id = valueAtPath(o, map.anchorId);
      const QString idText = id.isDouble() ? QString::number(static_cast<qint64>(id.toDouble())) : id.toString();
      if(!idText.isEmpty()) {
        c.anchor = map.anchorPrefix + idText;
      }
    }
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
  setLastPullComplete(truncatedReason.isEmpty());
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

namespace {

// The logins an issue is assigned to: every entry of `assignees`, plus the
// single `assignee` older APIs still fill in.
QStringList assigneeLogins(const QJsonObject& issue, const QString& loginKey) {
  QStringList out;
  const QJsonArray list = issue.value(QStringLiteral("assignees")).toArray();
  for(const auto& v : list) {
    const QString login = v.toObject().value(loginKey).toString();
    if(!login.isEmpty()) {
      out.append(login);
    }
  }
  const QString single = issue.value(QStringLiteral("assignee")).toObject().value(loginKey).toString();
  if(!single.isEmpty() && !out.contains(single, Qt::CaseInsensitive)) {
    out.append(single);
  }
  return out;
}

}  // namespace

void RestIssueProvider::withSelfLogin(const std::function<void(const QString&, int, const QString&)>& done) {
  if(!m_selfLogin.isEmpty()) {
    done(m_selfLogin, 200, QString());
    return;
  }
  QNetworkReply* reply = m_nam->get(buildRequest(resolvedBaseUrl() + m_desc.selfUserPath));
  connect(reply, &QNetworkReply::finished, this, [this, reply, done]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      const int status = replyHttpStatus(reply);
      done(QString(), status, describeReplyError(reply));
      return;
    }
    m_selfLogin = QJsonDocument::fromJson(reply->readAll()).object().value(m_desc.selfLoginKey).toString();
    done(m_selfLogin, 200, m_selfLogin.isEmpty() ? QStringLiteral("could not tell who is signed in") : QString());
  });
}

void RestIssueProvider::checkIssue(const QString& externalId, const QString& project) {
  const auto answer = [this, externalId, project](bool ok, int status, const QString& error, const QString& remote, int match) {
    emit issueChecked(externalId, project, ok, status, error, remote, match);
  };
  if(m_desc.issuePathTemplate.isEmpty()) {
    answer(false, 0, QStringLiteral("unsupported"), QString(), FilterUnknown);
    return;
  }
  // Same rules as the push: the issue's own repo, never a guess.
  const bool ownProject = !project.isEmpty() && !m_desc.scopeKey.isEmpty();
  if(inSelfScope() && !ownProject) {
    answer(false, -1, QStringLiteral("the issue's repo is unknown — sync it again first"), QString(), FilterUnknown);
    return;
  }
  if(!isConfigured() || externalId.isEmpty()) {
    answer(false, -1, QStringLiteral("not configured"), QString(), FilterUnknown);
    return;
  }
  QVariantMap extra;
  extra.insert(QStringLiteral("externalId"), externalId);
  if(ownProject) {
    extra.insert(m_desc.scopeKey, project);
  }
  const QString base = resolvedBaseUrl();
  QNetworkReply* reply = m_nam->get(buildRequest(base + expand(m_desc.issuePathTemplate, extra)));
  connect(reply, &QNetworkReply::finished, this, [this, reply, base, project, answer]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      const int status = replyHttpStatus(reply);
      answer(false, status, describeReplyError(reply), QString(), FilterUnknown);
      return;
    }
    const QByteArray raw = reply->readAll().trimmed();
    const QByteArray list = raw.startsWith('{') ? '[' + raw + ']' : raw;
    const QVector<ExternalTask> parsed =
        m_desc.parser ? m_desc.parser(list, base) : parseWithFieldMap(list, m_desc.fields, m_desc.id, base);
    if(parsed.size() != 1) {
      answer(false, -1, QStringLiteral("the tracker's answer did not describe the issue"), QString(), FilterUnknown);
      return;
    }
    const ExternalTask issue = parsed.first();
    if(!inSelfScope()) {
      // A repo/project filter takes every issue that lives there. The one the
      // card came from, or the one the issue answered from after a transfer,
      // has to be the configured one. A numeric GitLab id cannot be compared
      // with a path, so it is taken on trust: the issue answered from it.
      const QString configured = m_cfg.value(m_desc.scopeKey).toString();
      bool numeric = false;
      configured.toLongLong(&numeric);
      const auto differs = [&configured](const QString& where) {
        return !where.isEmpty() && where.compare(configured, Qt::CaseInsensitive) != 0;
      };
      const bool in = configured.isEmpty() || numeric || (!differs(project) && !differs(issue.project));
      answer(true, 200, QString(), issue.status, in ? FilterIn : FilterOut);
      return;
    }
    if(m_desc.selfUserPath.isEmpty() || m_desc.selfLoginKey.isEmpty()) {
      answer(true, 200, QString(), issue.status, FilterUnknown);
      return;
    }
    const QStringList assignees = assigneeLogins(QJsonDocument::fromJson(raw).object(), m_desc.selfLoginKey);
    const QString status = issue.status;
    withSelfLogin([answer, assignees, status](const QString& me, int httpStatus, const QString& error) {
      if(me.isEmpty()) {
        answer(false, httpStatus == 200 ? -1 : httpStatus, error, QString(), FilterUnknown);
        return;
      }
      answer(true, 200, QString(), status, assignees.contains(me, Qt::CaseInsensitive) ? FilterIn : FilterOut);
    });
  });
}

void RestIssueProvider::pushStatusChange(const QString& externalId, const QString& newStatus, const QString& project) {
  if(m_desc.pushPathTemplate.isEmpty()) {
    // Pull-only provider: report success without touching the remote so
    // moving a linked task never spams the log with "push failed".
    emit taskPushed(externalId, project, true, QStringLiteral("pull-only"), QString());
    return;
  }
  // The issue's own repo, when the card knows it. A "my issues" pull has no
  // configured repo to fall back on, so without it the write has nowhere to
  // go — and answering that as success hid a move that never left (INT-2).
  const bool ownProject = !project.isEmpty() && !m_desc.scopeKey.isEmpty();
  if(inSelfScope() && !ownProject) {
    emit taskPushed(externalId, project, false, QStringLiteral("the issue's repo is unknown — sync it again first"), QString());
    return;
  }
  if(!isConfigured() || externalId.isEmpty()) {
    emit taskPushed(externalId, project, false, QStringLiteral("not configured"), QString());
    return;
  }
  const QString state = m_desc.pushMap ? m_desc.pushMap(newStatus) : newStatus;
  QVariantMap extra;
  extra.insert(QStringLiteral("externalId"), externalId);
  extra.insert(QStringLiteral("state"), state);
  // expand() prefers `extra` over the config, so the issue's own repo wins.
  if(ownProject) {
    extra.insert(m_desc.scopeKey, project);
  }
  // Same base as pull and comments: GitLab with an empty Host is gitlab.com,
  // and a bare path has no scheme to send it with (INT-7).
  const QString base = resolvedBaseUrl();
  const QString url = base + expand(m_desc.pushPathTemplate, extra);

  QNetworkRequest req = buildRequest(url);
  QByteArray body;
  if(!m_desc.pushBodyTemplate.isEmpty()) {
    body = m_desc.pushBodyTemplate;
    body.replace("{state}", state.toUtf8());
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
  }
  QNetworkReply* reply = m_nam->sendCustomRequest(req, m_desc.pushMethod.toUtf8(), body);
  connect(reply, &QNetworkReply::finished, this, [this, reply, externalId, project, base]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      emit taskPushed(externalId, project, false, describeReplyError(reply), QString());
      return;
    }
    // The trackers with a push path answer with the updated issue. Read its
    // status the way a pull would, so the sync base is what the next pull
    // compares against (INT-3).
    QByteArray issue = reply->readAll().trimmed();
    if(issue.startsWith('{')) {
      issue = '[' + issue + ']';
    }
    const QVector<ExternalTask> parsed =
        m_desc.parser ? m_desc.parser(issue, base) : parseWithFieldMap(issue, m_desc.fields, m_desc.id, base);
    emit taskPushed(externalId, project, true, QString(), parsed.size() == 1 ? parsed.first().status : QString());
  });
}

}  // namespace heap::integrations
