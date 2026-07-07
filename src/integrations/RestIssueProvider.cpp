#include "integrations/RestIssueProvider.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

namespace heap::integrations {

namespace {

// Walk a dot-path ("status.name") through nested JSON objects and return the
// leaf value. An empty path or a missing key yields an undefined value.
QJsonValue valueAtPath(const QJsonObject& obj, const QString& path) {
  if(path.isEmpty()) {
    return {};
  }
  const QStringList parts = path.split('.');
  QJsonValue cur = obj;
  for(const QString& part : parts) {
    if(!cur.isObject()) {
      return {};
    }
    cur = cur.toObject().value(part);
  }
  return cur;
}

// Stringify a leaf: strings pass through, integral numbers lose the ".0", bools
// become "true"/"false". Objects/arrays/null → empty string.
QString leafToString(const QJsonValue& v) {
  if(v.isString()) {
    return v.toString();
  }
  if(v.isBool()) {
    return v.toBool() ? QStringLiteral("true") : QStringLiteral("false");
  }
  if(v.isDouble()) {
    const double d = v.toDouble();
    const auto asLong = static_cast<qlonglong>(d);
    if(static_cast<double>(asLong) == d) {
      return QString::number(asLong);
    }
    return QString::number(d);
  }
  return {};
}

QString fieldStr(const QJsonObject& obj, const QString& path) {
  return leafToString(valueAtPath(obj, path));
}

}  // namespace

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

    if(!map.updatedAt.isEmpty()) {
      t.updatedAt = QDateTime::fromString(fieldStr(o, map.updatedAt), Qt::ISODate);
    }

    if(!map.labels.isEmpty()) {
      const QJsonArray labels = valueAtPath(o, map.labels).toArray();
      for(const auto& lv : labels) {
        QString name;
        if(map.labelNameKey.isEmpty()) {
          name = lv.toString();
        } else if(lv.isObject()) {
          name = lv.toObject().value(map.labelNameKey).toString();
        }
        if(!name.isEmpty()) {
          t.labels.append(name);
        }
      }
    }
    out.append(t);
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
    emit connectionTested(reply->error() == QNetworkReply::NoError, reply->errorString());
  });
}

void RestIssueProvider::pullTasks() {
  if(!isConfigured()) {
    emit tasksFetched({});
    return;
  }
  const QString base = resolvedBaseUrl();
  const QString url = base + expand(listPath());
  QNetworkReply* reply = m_nam->get(buildRequest(url));
  connect(reply, &QNetworkReply::finished, this, [this, reply, base]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      emit tasksFetched({});
      return;
    }
    const QByteArray body = reply->readAll();
    if(m_desc.parser) {
      emit tasksFetched(m_desc.parser(body, base));
    } else {
      emit tasksFetched(parseWithFieldMap(body, m_desc.fields, m_desc.id, base));
    }
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
    emit taskPushed(externalId, reply->error() == QNetworkReply::NoError, reply->errorString());
  });
}

}  // namespace heap::integrations
