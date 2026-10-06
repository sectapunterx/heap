#include "notify/NotifyPayload.h"

#include <QStringList>
#include <QUrl>

#include <algorithm>

namespace heap::notify {

namespace {

QString pct(const QString& s) {
  return QString::fromLatin1(QUrl::toPercentEncoding(s));
}

QString esc(const QString& s) {
  return s.toHtmlEscaped();
}

// Toasts show at most five buttons; Windows rejects the whole toast past that.
constexpr qsizetype kMaxToastActions = 5;

}  // namespace

QString notifyUri(const QString& notificationId, const QString& actionId, const QString& dataDir) {
  QString uri = QLatin1String(kUriScheme) + QStringLiteral("://notify?id=") + pct(notificationId) + QStringLiteral("&action=") +
                pct(actionId.isEmpty() ? QString::fromLatin1(kDefaultAction) : actionId);
  if(!dataDir.isEmpty()) {
    uri += QStringLiteral("&dir=") + pct(dataDir);
  }
  return uri;
}

bool isNotifyUri(const QString& arg) {
  return arg.trimmed().startsWith(QLatin1String(kUriScheme) + QStringLiteral("://notify"), Qt::CaseInsensitive);
}

NotifyUri parseNotifyUri(const QString& uri) {
  NotifyUri out;
  const QUrl url(uri.trimmed(), QUrl::StrictMode);
  if(!url.isValid() || url.scheme().compare(QLatin1String(kUriScheme), Qt::CaseInsensitive) != 0 ||
     url.host() != QStringLiteral("notify")) {
    return out;
  }
  // The shell may add a slash before the query ("heap://notify/?id=…").
  if(!url.path().isEmpty() && url.path() != QStringLiteral("/")) {
    return out;
  }
  const QString query = url.query(QUrl::FullyEncoded);
  for(const QString& pair : query.split(QLatin1Char('&'), Qt::SkipEmptyParts)) {
    const qsizetype eq = pair.indexOf(QLatin1Char('='));
    if(eq <= 0) {
      continue;
    }
    const QString key = pair.left(eq);
    const QString value = QUrl::fromPercentEncoding(pair.mid(eq + 1).toUtf8());
    if(key == QStringLiteral("id")) {
      out.notificationId = value;
    } else if(key == QStringLiteral("action")) {
      out.actionId = value;
    } else if(key == QStringLiteral("dir")) {
      out.dataDir = value;
    }
  }
  if(out.notificationId.isEmpty()) {
    return out;
  }
  if(out.actionId.isEmpty()) {
    out.actionId = QString::fromLatin1(kDefaultAction);
  }
  out.ok = true;
  return out;
}

QString toastXml(const Notification& n, const QString& dataDir, const QString& logoPath) {
  QString xml = QStringLiteral("<toast launch=\"%1\" activationType=\"protocol\">").arg(esc(notifyUri(n.id, QString(), dataDir)));
  xml += QStringLiteral("<visual><binding template=\"ToastGeneric\">");
  xml += QStringLiteral("<text>%1</text>").arg(esc(n.title));
  if(!n.body.isEmpty()) {
    xml += QStringLiteral("<text>%1</text>").arg(esc(n.body));
  }
  if(!logoPath.isEmpty()) {
    xml += QStringLiteral("<image placement=\"appLogoOverride\" src=\"%1\"/>")
               .arg(esc(QUrl::fromLocalFile(logoPath).toString(QUrl::FullyEncoded)));
  }
  xml += QStringLiteral("</binding></visual>");
  if(!n.actions.isEmpty()) {
    xml += QStringLiteral("<actions>");
    const qsizetype count = std::min(n.actions.size(), kMaxToastActions);
    for(qsizetype i = 0; i < count; ++i) {
      const NotificationAction& a = n.actions.at(i);
      xml += QStringLiteral("<action content=\"%1\" arguments=\"%2\" activationType=\"protocol\"/>")
                 .arg(esc(a.label))
                 .arg(esc(notifyUri(n.id, a.id, dataDir)));
    }
    xml += QStringLiteral("</actions>");
  }
  xml += QStringLiteral("</toast>");
  return xml;
}

int snoozeMinutesFor(const QString& actionId, int shortMin, int longMin) {
  if(actionId == QLatin1String(kSnoozeShort)) {
    return std::clamp(shortMin, kMinSnoozeMin, kMaxSnoozeMin);
  }
  if(actionId == QLatin1String(kSnoozeLong)) {
    return std::clamp(longMin, kMinSnoozeMin, kMaxSnoozeMin);
  }
  if(actionId == QLatin1String(kLegacySnooze1h)) {
    return 60;
  }
  return 0;
}

QDateTime snoozeUntil(const QDateTime& now, int minutes) {
  return now.addSecs(60LL * std::clamp(minutes, kMinSnoozeMin, kMaxSnoozeMin));
}

QString snoozeLabel(int minutes, bool russian) {
  const int m = std::clamp(minutes, kMinSnoozeMin, kMaxSnoozeMin);
  if(m % 60 == 0) {
    return russian ? QStringLiteral("Отложить на %1 ч").arg(m / 60) : QStringLiteral("Snooze %1 h").arg(m / 60);
  }
  return russian ? QStringLiteral("Отложить на %1 мин").arg(m) : QStringLiteral("Snooze %1 min").arg(m);
}

void upsertSnooze(QVector<SnoozedReminder>& pending, const SnoozedReminder& s) {
  pending.removeIf([&s](const SnoozedReminder& p) {
    return p.id == s.id;
  });
  pending.append(s);
}

QVector<SnoozedReminder> takeDueSnoozes(QVector<SnoozedReminder>& pending, const QDateTime& now) {
  QVector<SnoozedReminder> due;
  QVector<SnoozedReminder> left;
  for(const SnoozedReminder& s : pending) {
    (s.fireAt.isValid() && s.fireAt <= now ? due : left).append(s);
  }
  pending = left;
  std::sort(due.begin(), due.end(), [](const SnoozedReminder& a, const SnoozedReminder& b) {
    return a.fireAt < b.fireAt;
  });
  return due;
}

bool NotificationCenter::handleActivationUri(const QString& uri) {
  const NotifyUri parsed = parseNotifyUri(uri);
  if(!parsed.ok) {
    return false;
  }
  if(parsed.actionId == QLatin1String(kDefaultAction)) {
    emit activated(parsed.notificationId);
  } else {
    emit actionInvoked(parsed.notificationId, parsed.actionId);
  }
  return true;
}

}  // namespace heap::notify
