#pragma once

#include <QDate>
#include <QHash>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVector>

// A useful subset of RFC 5545 recurrence rules.
//
// Events repeat — a standup, a 1:1, a weekly review — and heap had no way to
// say so: only tasks had a recurrence, it was a chrono token rather than a
// rule, and it could only answer "what is the next one?". A calendar needs the
// other question: which occurrences fall inside the fortnight I am looking at.
//
// The subset is FREQ=DAILY|WEEKLY|MONTHLY|YEARLY with INTERVAL, BYDAY, COUNT
// and UNTIL. That is what an .ics from Google or Outlook carries for the
// meetings people actually keep, and it is small enough to be read at a glance.
// Anything unrecognised parses to an invalid rule, and the caller shows a
// single event rather than guessing.
namespace heap::cal {

struct RRule {
  enum Freq { None, Daily, Weekly, Monthly, Yearly };

  Freq freq = None;
  int interval = 1;
  // Qt weekday numbers (Mon=1 … Sun=7). Empty means "the weekday of the start
  // date", which is what a WEEKLY rule with no BYDAY means.
  QVector<int> byDay;
  int count = 0;  // 0 = unbounded
  QDate until;    // invalid = unbounded

  bool isValid() const {
    return freq != None;
  }
};

namespace detail {

inline int dayNumberFor(const QString& token) {
  static const QHash<QString, int> kDays = {{QStringLiteral("MO"), 1},
                                            {QStringLiteral("TU"), 2},
                                            {QStringLiteral("WE"), 3},
                                            {QStringLiteral("TH"), 4},
                                            {QStringLiteral("FR"), 5},
                                            {QStringLiteral("SA"), 6},
                                            {QStringLiteral("SU"), 7}};
  // BYDAY can carry an ordinal ("2TH" = the second Thursday). The ordinal is
  // not supported, and dropping it would silently turn that into "every
  // Thursday" — a meeting four times as often as it should be. Reject instead.
  const auto it = kDays.constFind(token.trimmed().toUpper());
  return it == kDays.constEnd() ? 0 : *it;
}

}  // namespace detail

// Parses "FREQ=WEEKLY;BYDAY=MO,WE;INTERVAL=2". Returns an invalid rule for
// anything this subset does not cover.
inline RRule parseRRule(const QString& text) {
  RRule rule;
  if(text.trimmed().isEmpty()) {
    return rule;
  }
  QHash<QString, QString> parts;
  for(const QString& chunk : text.split(QChar(';'), Qt::SkipEmptyParts)) {
    const int eq = chunk.indexOf(QChar('='));
    if(eq <= 0) {
      return {};  // malformed
    }
    parts.insert(chunk.left(eq).trimmed().toUpper(), chunk.mid(eq + 1).trimmed());
  }

  static const QHash<QString, RRule::Freq> kFreqs = {{QStringLiteral("DAILY"), RRule::Daily},
                                                     {QStringLiteral("WEEKLY"), RRule::Weekly},
                                                     {QStringLiteral("MONTHLY"), RRule::Monthly},
                                                     {QStringLiteral("YEARLY"), RRule::Yearly}};
  const auto freqIt = kFreqs.constFind(parts.value(QStringLiteral("FREQ")).toUpper());
  if(freqIt == kFreqs.constEnd()) {
    return {};
  }
  rule.freq = *freqIt;

  if(parts.contains(QStringLiteral("INTERVAL"))) {
    bool ok = false;
    const int n = parts.value(QStringLiteral("INTERVAL")).toInt(&ok);
    if(!ok || n < 1) {
      return {};
    }
    rule.interval = n;
  }

  if(parts.contains(QStringLiteral("BYDAY"))) {
    for(const QString& token : parts.value(QStringLiteral("BYDAY")).split(QChar(','), Qt::SkipEmptyParts)) {
      const int day = detail::dayNumberFor(token);
      if(day == 0) {
        return {};  // an ordinal like "2TH", or junk
      }
      if(!rule.byDay.contains(day)) {
        rule.byDay.append(day);
      }
    }
    if(rule.byDay.isEmpty()) {
      return {};
    }
    std::sort(rule.byDay.begin(), rule.byDay.end());
  }

  if(parts.contains(QStringLiteral("COUNT"))) {
    bool ok = false;
    const int n = parts.value(QStringLiteral("COUNT")).toInt(&ok);
    if(!ok || n < 1) {
      return {};
    }
    rule.count = n;
  }

  if(parts.contains(QStringLiteral("UNTIL"))) {
    // Both the date and the date-time forms; only the date part is used,
    // because heap's events are anchored to a date plus an hour of their own.
    const QString raw = parts.value(QStringLiteral("UNTIL")).left(8);
    const QDate d = QDate::fromString(raw, QStringLiteral("yyyyMMdd"));
    if(!d.isValid()) {
      return {};
    }
    rule.until = d;
  }

  return rule;
}

inline QString toRRuleText(const RRule& rule) {
  if(!rule.isValid()) {
    return {};
  }
  static const QHash<int, QString> kNames = {{RRule::Daily, QStringLiteral("DAILY")},
                                             {RRule::Weekly, QStringLiteral("WEEKLY")},
                                             {RRule::Monthly, QStringLiteral("MONTHLY")},
                                             {RRule::Yearly, QStringLiteral("YEARLY")}};
  QStringList parts{QStringLiteral("FREQ=") + kNames.value(rule.freq)};
  if(rule.interval > 1) {
    parts << QStringLiteral("INTERVAL=") + QString::number(rule.interval);
  }
  if(!rule.byDay.isEmpty()) {
    static const QHash<int, QString> kDays = {{1, QStringLiteral("MO")},
                                              {2, QStringLiteral("TU")},
                                              {3, QStringLiteral("WE")},
                                              {4, QStringLiteral("TH")},
                                              {5, QStringLiteral("FR")},
                                              {6, QStringLiteral("SA")},
                                              {7, QStringLiteral("SU")}};
    QStringList days;
    for(int d : rule.byDay) {
      days << kDays.value(d);
    }
    parts << QStringLiteral("BYDAY=") + days.join(QChar(','));
  }
  if(rule.count > 0) {
    parts << QStringLiteral("COUNT=") + QString::number(rule.count);
  }
  if(rule.until.isValid()) {
    parts << QStringLiteral("UNTIL=") + rule.until.toString(QStringLiteral("yyyyMMdd"));
  }
  return parts.join(QChar(';'));
}

// Every occurrence of `rule` starting at `start` that falls within [from, to].
//
// COUNT is counted from the start of the series, not from `from` — the tenth
// occurrence is the tenth whatever window is being looked at, otherwise
// scrolling the calendar would change how many there are.
//
// The walk is bounded: a rule whose interval never advances, or a window far
// past a COUNT-limited series, must not spin.
inline QVector<QDate> expand(const RRule& rule, const QDate& start, const QDate& from, const QDate& to) {
  QVector<QDate> out;
  if(!rule.isValid() || !start.isValid() || !from.isValid() || !to.isValid() || to < from) {
    return out;
  }

  const QDate hardEnd = rule.until.isValid() ? std::min(to, rule.until) : to;
  if(hardEnd < start) {
    return out;
  }

  int emitted = 0;  // how many occurrences the series has produced so far
  const auto take = [&](const QDate& d) {
    if(d < start) {
      return true;  // before the series began
    }
    if(rule.until.isValid() && d > rule.until) {
      return false;
    }
    ++emitted;
    if(rule.count > 0 && emitted > rule.count) {
      return false;
    }
    if(d >= from && d <= hardEnd) {
      out.append(d);
    }
    return true;
  };

  // A guard rather than a correctness bound: ~10 years of daily occurrences.
  constexpr int kMaxSteps = 4000;

  if(rule.freq == RRule::Weekly) {
    QVector<int> days = rule.byDay;
    if(days.isEmpty()) {
      days.append(start.dayOfWeek());
    }
    // Weeks are counted from the week the series starts in, so INTERVAL=2
    // means "every other week of the series", not "every other week of the
    // year" — which would shift depending on where the year began.
    const QDate weekOfStart = start.addDays(-(start.dayOfWeek() - 1));
    QDate week = weekOfStart;
    for(int step = 0; step < kMaxSteps; ++step) {
      if(week > hardEnd && week > from) {
        break;
      }
      for(int day : days) {
        const QDate d = week.addDays(day - 1);
        if(d > hardEnd && d > from) {
          continue;
        }
        if(!take(d)) {
          return out;
        }
      }
      if(week.addDays(7 * rule.interval) > hardEnd) {
        break;
      }
      week = week.addDays(7 * rule.interval);
    }
    return out;
  }

  QDate d = start;
  for(int step = 0; step < kMaxSteps && d <= hardEnd; ++step) {
    if(!take(d)) {
      return out;
    }
    switch(rule.freq) {
      case RRule::Daily:
        d = d.addDays(rule.interval);
        break;
      case RRule::Monthly:
        // addMonths clamps: the 31st in a 30-day month lands on the 30th,
        // which is what every calendar does with a monthly meeting.
        d = d.addMonths(rule.interval);
        break;
      case RRule::Yearly:
        d = d.addYears(rule.interval);
        break;
      default:
        return out;
    }
  }
  return out;
}

// The first occurrence strictly after `after`, or an invalid date when the
// series has ended. Used where only "the next one" is wanted.
inline QDate nextAfter(const RRule& rule, const QDate& start, const QDate& after) {
  if(!rule.isValid() || !start.isValid() || !after.isValid()) {
    return {};
  }
  // A year is enough for every frequency in this subset except a long
  // INTERVAL on YEARLY, which is handled by widening once.
  for(int years : {1, 4, 25}) {
    const QVector<QDate> dates = expand(rule, start, after.addDays(1), after.addYears(years));
    if(!dates.isEmpty()) {
      return dates.first();
    }
  }
  return {};
}

}  // namespace heap::cal
