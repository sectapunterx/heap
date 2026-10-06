#include "integrations/SyncHealth.h"

namespace heap::integrations {

namespace {

QString pick(bool ru, const char* en, const char* rus) {
  return QString::fromUtf8(ru ? rus : en);
}

}  // namespace

FailureKind classifyFailure(int httpStatus, const QString& error) {
  if(httpStatus == 401) {
    return FailureKind::Auth;
  }
  if(httpStatus == 429 || (httpStatus == 403 && error.contains(QStringLiteral("rate limit"), Qt::CaseInsensitive))) {
    return FailureKind::RateLimited;
  }
  if(httpStatus == 403) {
    return FailureKind::Forbidden;
  }
  if(httpStatus == 404) {
    return FailureKind::NotFound;
  }
  if(httpStatus >= 500 && httpStatus <= 599) {
    return FailureKind::Server;
  }
  if(httpStatus <= 0) {
    return error.isEmpty() ? FailureKind::None : FailureKind::Network;
  }
  return FailureKind::Other;
}

QString failureText(FailureKind kind, bool ru) {
  switch(kind) {
    case FailureKind::Auth:
      return pick(ru, "The sign-in was rejected or has expired — sign in again", "Вход отклонён или истёк — войдите снова");
    case FailureKind::Forbidden:
      return pick(ru, "Signed in, but this token is not allowed to read it", "Вход есть, но у токена нет доступа");
    case FailureKind::NotFound:
      return pick(ru, "The repo or project was not found — check the settings", "Репозиторий или проект не найден — проверьте настройки");
    case FailureKind::RateLimited:
      return pick(ru, "Too many requests — the tracker asked to wait", "Слишком много запросов — трекер просит подождать");
    case FailureKind::Server:
      return pick(ru, "The tracker's server failed — not on your side", "Сбой на сервере трекера — не на вашей стороне");
    case FailureKind::Network:
      return pick(ru, "No connection to the tracker", "Нет связи с трекером");
    case FailureKind::Other:
      return pick(ru, "The last sync failed", "Последняя синхронизация не удалась");
    case FailureKind::None:
      break;
  }
  return {};
}

QString relativeAge(const QDateTime& then, const QDateTime& now, bool ru) {
  if(!then.isValid()) {
    return {};
  }
  const qint64 secs = qMax<qint64>(0, then.secsTo(now));
  if(secs < 60) {
    return pick(ru, "just now", "только что");
  }
  const qint64 mins = secs / 60;
  if(mins < 60) {
    return ru ? QStringLiteral("%1 мин назад").arg(mins) : QStringLiteral("%1 min ago").arg(mins);
  }
  const qint64 hours = mins / 60;
  if(hours < 24) {
    return ru ? QStringLiteral("%1 ч назад").arg(hours) : QStringLiteral("%1 h ago").arg(hours);
  }
  const qint64 days = hours / 24;
  return ru ? QStringLiteral("%1 дн назад").arg(days) : QStringLiteral("%1 d ago").arg(days);
}

QString expiryText(const QDateTime& expires, const QDateTime& now, bool ru) {
  if(!expires.isValid()) {
    return {};
  }
  const qint64 secs = now.secsTo(expires);
  if(secs <= 0) {
    return pick(ru, "the token has expired", "срок токена истёк");
  }
  const qint64 mins = secs / 60;
  if(mins < 60) {
    return ru ? QStringLiteral("токен истекает через %1 мин").arg(qMax<qint64>(1, mins))
              : QStringLiteral("token expires in %1 min").arg(qMax<qint64>(1, mins));
  }
  const qint64 hours = mins / 60;
  if(hours < 48) {
    return ru ? QStringLiteral("токен истекает через %1 ч").arg(hours) : QStringLiteral("token expires in %1 h").arg(hours);
  }
  return ru ? QStringLiteral("токен истекает через %1 дн").arg(hours / 24) : QStringLiteral("token expires in %1 d").arg(hours / 24);
}

void ProviderHealth::recordOk(const QDateTime& at, int items) {
  lastOk = at;
  lastItems = items;
}

void ProviderHealth::recordFailure(const QDateTime& at, int httpStatus, const QString& error) {
  lastFailureAt = at;
  lastFailure = classifyFailure(httpStatus, error);
  if(lastFailure == FailureKind::None) {
    lastFailure = FailureKind::Other;
  }
  lastError = error;
}

bool ProviderHealth::failing() const {
  return lastFailure != FailureKind::None && lastFailureAt.isValid() && (!lastOk.isValid() || lastFailureAt > lastOk);
}

}  // namespace heap::integrations
