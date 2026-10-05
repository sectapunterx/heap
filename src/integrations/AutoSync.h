#pragma once

#include <QDateTime>
#include <QtGlobal>

namespace heap::integrations {

// Periodic tracker sync at any cadence from a few minutes to a month
// (APP-123). A QTimer cannot wait a month (its interval is an int of
// milliseconds, under 25 days), and a restart would start the wait over, so
// the timer only looks — at most hourly — and the time of the last sync,
// kept on disk, says whether one is due.

inline constexpr int kMaxAutoSyncMinutes = 31 * 24 * 60;

// How often the timer looks for a sync of every `everyMinutes`: at the
// cadence itself up to an hour, hourly beyond.
inline int autoSyncCheckMinutes(int everyMinutes) {
  return qBound(1, everyMinutes, 60);
}

// Whether a sync is due at `now`. Never synced counts as due. Half a minute
// of slack, so a timer that fires a hair early does not push the sync back a
// whole check.
inline bool autoSyncDue(const QDateTime& last, const QDateTime& now, int everyMinutes) {
  if(everyMinutes <= 0) {
    return false;
  }
  return !last.isValid() || last.secsTo(now) >= static_cast<qint64>(everyMinutes) * 60 - 30;
}

}  // namespace heap::integrations
