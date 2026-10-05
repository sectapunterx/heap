#pragma once

#include "Models.h"

#include "cal/IcsCodec.h"

#include <QSet>
#include <QString>
#include <QUrl>
#include <QVector>

// A calendar heap reads from a link (APP-118): Outlook's "Publish calendar"
// ICS URL, or Google's / iCloud's secret address. The calendar there is the
// truth and heap only shows it, so its events are kept apart from the user's
// own by their id — "sub:<subscription>:<uid>" — and every write path refuses
// them. A refresh replaces the subscription's events wholesale: what the feed
// no longer carries was moved or cancelled over there.
namespace heap::cal {

inline QString subscriptionPrefix(const QString& subId) {
  return QStringLiteral("sub:") + subId + QLatin1Char(':');
}

inline bool isSubscriptionEventId(const QString& id) {
  return id.startsWith(QStringLiteral("sub:"));
}

// The subscription an event id belongs to, or empty for the user's own.
inline QString subscriptionOfEventId(const QString& id) {
  if(!isSubscriptionEventId(id)) {
    return {};
  }
  const qsizetype end = id.indexOf(QLatin1Char(':'), 4);
  return end < 0 ? QString() : id.mid(4, end - 4);
}

// webcal:// is how Outlook and Apple hand the link out; it is plain HTTPS.
// Anything that is not then http(s) is not a feed heap fetches.
inline QUrl subscriptionFetchUrl(const QString& link) {
  QString s = link.trimmed();
  if(s.startsWith(QStringLiteral("webcals://"), Qt::CaseInsensitive)) {
    s = QStringLiteral("https://") + s.mid(10);
  } else if(s.startsWith(QStringLiteral("webcal://"), Qt::CaseInsensitive)) {
    s = QStringLiteral("https://") + s.mid(9);
  }
  QUrl url(s, QUrl::StrictMode);
  if(!url.isValid() || url.host().isEmpty() || (url.scheme() != QStringLiteral("https") && url.scheme() != QStringLiteral("http"))) {
    return {};
  }
  return url;
}

// The events a fetched feed stands for, as subscription `subId`'s: ids and
// series links prefixed, the occurrences it cancels in a series it carries
// turned into exdates, and nothing attributed to a profile — a meeting shows
// whichever profile is open.
inline QVector<CalEvent> subscriptionEvents(const IcsImport& parsed, const QString& subId) {
  const QString prefix = subscriptionPrefix(subId);
  QVector<CalEvent> out;
  out.reserve(parsed.events.size());
  for(CalEvent e : parsed.events) {
    e.id = prefix + e.id;
    if(!e.masterId.isEmpty()) {
      e.masterId = prefix + e.masterId;
    }
    e.profileId.clear();
    e.taskId.clear();
    out.append(e);
  }
  for(const IcsImport::Cancelled& c : parsed.cancelled) {
    for(CalEvent& e : out) {
      if(e.id == prefix + c.masterId && e.masterId.isEmpty() && !e.exdates.contains(c.date)) {
        e.exdates.append(c.date);
      }
    }
  }
  // Overrides whose series the feed does not carry would float on their own
  // and outlive a cancelled series; the feed is the whole truth, so they go.
  QSet<QString> ids;
  for(const CalEvent& e : out) {
    ids.insert(e.id);
  }
  QVector<CalEvent> kept;
  kept.reserve(out.size());
  for(const CalEvent& e : out) {
    if(e.masterId.isEmpty() || ids.contains(e.masterId)) {
      kept.append(e);
    }
  }
  return kept;
}

}  // namespace heap::cal
