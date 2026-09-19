#pragma once

#include <QByteArray>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QString>
#include <QStringList>

// Turning a failed tracker request into something a user can act on.
//
// Every provider used to report Qt's bare errorString(), which says "server
// replied: Unauthorized" and nothing about *why* — and a failed pull didn't
// even get that far: it emitted an empty task list, so a 401 and an empty
// backlog both surfaced as "Synced 0 issue(s)". These helpers pull the message
// out of whatever error envelope the provider uses and prefix the HTTP status.
//
// Header-only on purpose: tests/CMakeLists.txt lists the integration sources
// file-by-file across ~10 targets, so a new .cpp would have to be added to all
// of them.

namespace heap::integrations {

namespace detail {

// Longer than this and the toast stops being readable; provider messages are
// usually one short sentence, but Jira happily returns a paragraph.
constexpr int kMaxErrorMessageLength = 200;

inline QString clampMessage(QString msg) {
  msg = msg.simplified();
  if(msg.size() > kMaxErrorMessageLength) {
    msg.truncate(kMaxErrorMessageLength);
    msg += QStringLiteral("…");
  }
  return msg;
}

// Pull a human message out of one error object. Providers all disagree on the
// key, so try each shape in turn:
//   Jira        {"errorMessages":["..."], "errors":{"jql":"..."}}
//   GitHub      {"message":"Bad credentials"}
//   GitLab      {"message":"401 Unauthorized"} | {"error_description":"..."}
//   Asana/Gitea {"errors":[{"message":"..."}]}
//   Sentry      {"detail":"..."}
//   ClickUp     {"err":"Team not authorized"}
inline QString messageFromObject(const QJsonObject& obj) {
  const QJsonArray errorMessages = obj.value(QStringLiteral("errorMessages")).toArray();
  if(!errorMessages.isEmpty()) {
    return errorMessages.first().toString();
  }

  const QJsonValue errors = obj.value(QStringLiteral("errors"));
  if(errors.isObject()) {
    // Jira field errors: {"jql":"The query is unbounded…"} — keep the field
    // name, it's the only hint about which input is wrong.
    QStringList parts;
    const QJsonObject fields = errors.toObject();
    for(auto it = fields.constBegin(); it != fields.constEnd(); ++it) {
      parts.append(it.key() + QStringLiteral(": ") + it.value().toString());
    }
    if(!parts.isEmpty()) {
      return parts.join(QStringLiteral("; "));
    }
  } else if(errors.isArray() && !errors.toArray().isEmpty()) {
    const QJsonValue first = errors.toArray().first();
    if(first.isString()) {
      return first.toString();
    }
    const QString nested = first.toObject().value(QStringLiteral("message")).toString();
    if(!nested.isEmpty()) {
      return nested;
    }
  }

  for(const auto* key : {"message", "detail", "error_description", "err", "error"}) {
    const QJsonValue v = obj.value(QLatin1String(key));
    if(v.isString() && !v.toString().isEmpty()) {
      return v.toString();
    }
  }
  return {};
}

inline QString messageFromBody(const QByteArray& body) {
  if(body.isEmpty()) {
    return {};
  }
  const QJsonDocument doc = QJsonDocument::fromJson(body);
  if(doc.isObject()) {
    return messageFromObject(doc.object());
  }
  if(doc.isArray() && !doc.array().isEmpty() && doc.array().first().isObject()) {
    return messageFromObject(doc.array().first().toObject());
  }
  // Not JSON (Trello answers in plain text, proxies answer in HTML). A single
  // short line is worth showing; anything bigger is markup, not a message.
  const QString text = QString::fromUtf8(body).simplified();
  if(text.isEmpty() || text.startsWith(QLatin1Char('<')) || text.size() > kMaxErrorMessageLength) {
    return {};
  }
  return text;
}

// What the status code alone tells the user, when the body says nothing.
inline QString hintForStatus(int status) {
  switch(status) {
    case 400:
      return QStringLiteral("bad request — check the query or filter");
    case 401:
      return QStringLiteral("unauthorized — check the token");
    case 403:
      return QStringLiteral("forbidden — the token is missing a required scope");
    case 404:
      return QStringLiteral("not found — check the URL, project or repo");
    case 429:
      return QStringLiteral("rate limited — try again in a few minutes");
    default:
      return {};
  }
}

}  // namespace detail

// "HTTP 401 — Bad credentials". `status` 0 means the request never got a
// response (DNS, TLS, offline), in which case `fallback` (Qt's errorString) is
// all there is.
inline QString describeHttpError(int status, const QByteArray& body, const QString& fallback) {
  QString message = detail::messageFromBody(body);
  if(message.isEmpty()) {
    message = detail::hintForStatus(status);
  }
  if(status <= 0) {
    return detail::clampMessage(message.isEmpty() ? fallback : message);
  }
  const QString prefix = QStringLiteral("HTTP %1").arg(status);
  if(message.isEmpty()) {
    message = fallback;
  }
  if(message.isEmpty()) {
    return prefix;
  }
  return prefix + QStringLiteral(" — ") + detail::clampMessage(message);
}

// The status code of a finished reply, or 0 when it never reached the server.
inline int replyHttpStatus(QNetworkReply* reply) {
  return reply ? reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() : 0;
}

// Consumes the reply body — call once, on a reply that has finished.
inline QString describeReplyError(QNetworkReply* reply) {
  if(!reply) {
    return {};
  }
  return describeHttpError(replyHttpStatus(reply), reply->readAll(), reply->errorString());
}

}  // namespace heap::integrations
