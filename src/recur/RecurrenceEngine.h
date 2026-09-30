#pragma once

#include <QDate>
#include <QHash>
#include <QString>

// Pure recurrence engine (HEAP-77). Given a recurrence token produced by the
// chrono parser (heap::chrono, e.g. "every:weekday") and a base date, returns
// the next occurrence's date. Header-only + inline so it needs no library or
// test wiring — include and call. Returns an invalid QDate for unknown/empty
// tokens (the caller treats that as "no recurrence").
namespace heap::recur {

inline QDate nextOccurrence(const QString& recurrence, const QDate& from) {
  if(recurrence.isEmpty() || !from.isValid()) {
    return {};
  }
  const QString r = recurrence.trimmed().toLower();
  if(r == QStringLiteral("every:day")) {
    return from.addDays(1);
  }
  if(r == QStringLiteral("every:week")) {
    return from.addDays(7);
  }
  // Monthly. "every:month:15" is the 15th of every month, clamped to the last
  // day of a shorter month and back on the 15th the month after; plain
  // "every:month" keeps the day of `from` the same way addMonths does.
  if(r == QStringLiteral("every:month")) {
    return from.addMonths(1);
  }
  if(r.startsWith(QStringLiteral("every:month:"))) {
    bool ok = false;
    const int day = r.mid(12).toInt(&ok);
    if(!ok || day < 1 || day > 31) {
      return {};
    }
    // The first such day strictly after `from`: this month's if it is still
    // ahead, else next month's.
    for(int k = 0; k < 2; ++k) {
      const QDate first = QDate(from.year(), from.month(), 1).addMonths(k);
      const QDate cand(first.year(), first.month(), qMin(day, first.daysInMonth()));
      if(cand > from) {
        return cand;
      }
    }
    return {};
  }
  if(r == QStringLiteral("every:weekday")) {
    QDate d = from.addDays(1);
    while(d.dayOfWeek() > 5) {  // Qt::Saturday=6, Qt::Sunday=7 → skip
      d = d.addDays(1);
    }
    return d;
  }
  // "every:<dow>" — the next date strictly after `from` on that weekday.
  static const QHash<QString, int> kDow = {{QStringLiteral("mon"), 1},
                                           {QStringLiteral("tue"), 2},
                                           {QStringLiteral("wed"), 3},
                                           {QStringLiteral("thu"), 4},
                                           {QStringLiteral("fri"), 5},
                                           {QStringLiteral("sat"), 6},
                                           {QStringLiteral("sun"), 7}};
  if(r.startsWith(QStringLiteral("every:"))) {
    const auto it = kDow.constFind(r.mid(6));
    if(it != kDow.constEnd()) {
      int delta = (it.value() - from.dayOfWeek() + 7) % 7;
      if(delta == 0) {
        delta = 7;  // land on the following week, never the same day
      }
      return from.addDays(delta);
    }
  }
  return {};
}

// The first occurrence after `from` that is also after `today`. Completing a
// weekly task three weeks late must not spawn a copy that is born overdue; it
// skips to the next one still ahead. Always at least one step past `from`.
inline QDate nextOccurrenceAfter(const QString& recurrence, const QDate& from, const QDate& today) {
  QDate d = nextOccurrence(recurrence, from);
  // Daily over ten years is the longest walk that can be asked for; the cap
  // only guards against a token that stops advancing.
  for(int guard = 0; d.isValid() && today.isValid() && d <= today && guard < 4000; ++guard) {
    const QDate n = nextOccurrence(recurrence, d);
    if(!n.isValid() || n <= d) {
      break;
    }
    d = n;
  }
  return d;
}

// True when `recurrence` is a token this engine understands.
inline bool isRecurring(const QString& recurrence) {
  return nextOccurrence(recurrence, QDate(2000, 1, 1)).isValid();
}

}  // namespace heap::recur
