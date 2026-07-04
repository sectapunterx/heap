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

// True when `recurrence` is a token this engine understands.
inline bool isRecurring(const QString& recurrence) {
  return nextOccurrence(recurrence, QDate(2000, 1, 1)).isValid();
}

}  // namespace heap::recur
