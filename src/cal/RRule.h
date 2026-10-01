#pragma once

#include <QDate>
#include <QDateTime>
#include <QHash>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QTimeZone>
#include <QVector>

#include <algorithm>

// RFC 5545 recurrence rules, for events that repeat on days.
//
// Events repeat — a standup, a 1:1, a weekly review — and heap had no way to
// say so: only tasks had a recurrence, it was a chrono token rather than a
// rule, and it could only answer "what is the next one?". A calendar needs the
// other question: which occurrences fall inside the fortnight I am looking at.
//
// Supported: FREQ=DAILY|WEEKLY|MONTHLY|YEARLY with INTERVAL, COUNT, UNTIL,
// BYDAY (with ordinals — "2TH", "-1FR" — where the RFC allows them), BYMONTHDAY
// (lists, negative days from the end of the month), BYMONTH (lists), BYSETPOS
// and WKST. That is every rule Google, Outlook and Apple write for meetings
// people keep. Anything else — an hourly rule, BYWEEKNO, BYYEARDAY — parses to
// an invalid rule with a reason, and the caller shows a single event and says
// so rather than guessing: a rule read half-way is a meeting on the wrong days.
//
// Semantics follow the RFC, not a friendlier variant of it:
//   * DTSTART is always the first occurrence and counts toward COUNT, even when
//     it is not itself one of the rule's days.
//   * A day the rule names that a month does not have is skipped:
//     BYMONTHDAY=31 has no April occurrence, as in Google and Apple.
//     BYMONTHDAY=-1 is how to say "the last day of the month". Only the day a
//     plain MONTHLY/YEARLY rule borrows from DTSTART clamps (see
//     monthCandidates).
namespace heap::cal {

// A BYDAY entry: a weekday (Qt numbering, Mon=1 … Sun=7) with an optional
// ordinal. `ord` 0 means "every such weekday"; 2 means the second one in the
// month (or year), -1 the last.
struct WeekdayNum {
  int ord = 0;
  int day = 0;

  bool operator==(const WeekdayNum&) const = default;
};

struct RRule {
  enum Freq { None, Daily, Weekly, Monthly, Yearly };

  Freq freq = None;
  int interval = 1;
  // Sorted by (ord, day). Empty means "the weekday of the start date" for a
  // WEEKLY rule and "not restricted by weekday" for the others.
  QVector<WeekdayNum> byDay;
  QVector<int> byMonthDay;  // 1..31 or -31..-1
  QVector<int> byMonth;     // 1..12
  QVector<int> bySetPos;    // ±1..366
  int wkst = 1;             // the day a week starts on, for WEEKLY INTERVAL>1
  int count = 0;            // 0 = unbounded
  // The last day an occurrence may fall on (inclusive). When the text carried
  // an exact UTC instant, `untilAt` holds it and `until` is a loose day bound
  // the date walk can use; the caller, which knows the events' clock time and
  // zone, drops an occurrence starting after `untilAt`.
  QDate until;
  QDateTime untilAt;

  bool isValid() const {
    return freq != None;
  }

  // Ends the series on `day` (inclusive), whichever way it ended before.
  void endOn(const QDate& day) {
    until = day;
    untilAt = QDateTime();
    count = 0;  // an UNTIL and a COUNT together would fight
  }

  // The weekdays without ordinals, in order. What a weekday picker shows.
  QVector<int> plainDays() const {
    QVector<int> out;
    for(const WeekdayNum& w : byDay) {
      if(w.ord == 0 && !out.contains(w.day)) {
        out.append(w.day);
      }
    }
    std::sort(out.begin(), out.end());
    return out;
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
  const auto it = kDays.constFind(token.trimmed().toUpper());
  return it == kDays.constEnd() ? 0 : *it;
}

inline QString dayToken(int day) {
  static const QString kNames[] = {QString(),
                                   QStringLiteral("MO"),
                                   QStringLiteral("TU"),
                                   QStringLiteral("WE"),
                                   QStringLiteral("TH"),
                                   QStringLiteral("FR"),
                                   QStringLiteral("SA"),
                                   QStringLiteral("SU")};
  return (day >= 1 && day <= 7) ? kNames[day] : QString();
}

// "2TH" → {2, 4}; "-1FR" → {-1, 5}; "MO" → {0, 1}. An invalid token gives
// day 0.
inline WeekdayNum parseWeekdayNum(const QString& raw) {
  const QString t = raw.trimmed().toUpper();
  if(t.size() < 2) {
    return {};
  }
  const int day = dayNumberFor(t.right(2));
  if(day == 0) {
    return {};
  }
  const QString num = t.left(t.size() - 2);
  if(num.isEmpty()) {
    return {0, day};
  }
  bool ok = false;
  const int ord = num.toInt(&ok);  // accepts a leading + or -
  if(!ok || ord == 0 || ord < -53 || ord > 53) {
    return {};
  }
  return {ord, day};
}

inline bool parseIntList(const QString& raw, int lo, int hi, QVector<int>* out) {
  for(const QString& piece : raw.split(QChar(','), Qt::SkipEmptyParts)) {
    bool ok = false;
    const int n = piece.trimmed().toInt(&ok);
    if(!ok || n == 0 || n < lo || n > hi) {
      return false;
    }
    if(!out->contains(n)) {
      out->append(n);
    }
  }
  std::sort(out->begin(), out->end());
  return !out->isEmpty();
}

}  // namespace detail

// Parses "FREQ=WEEKLY;BYDAY=MO,WE;INTERVAL=2". Returns an invalid rule for
// anything outside what is supported; `why`, when given, receives a short
// English reason naming the part that was not understood.
inline RRule parseRRule(const QString& text, QString* why = nullptr) {
  const auto fail = [why](const QString& reason) {
    if(why != nullptr) {
      *why = reason;
    }
    return RRule{};
  };
  if(text.trimmed().isEmpty()) {
    return fail(QStringLiteral("empty rule"));
  }
  RRule rule;
  QHash<QString, QString> parts;
  QString body = text.trimmed();
  if(body.startsWith(QLatin1String("RRULE:"), Qt::CaseInsensitive)) {
    body = body.mid(6);
  }
  for(const QString& chunk : body.split(QChar(';'), Qt::SkipEmptyParts)) {
    const int eq = chunk.indexOf(QChar('='));
    if(eq <= 0) {
      return fail(QStringLiteral("malformed part \"%1\"").arg(chunk));
    }
    parts.insert(chunk.left(eq).trimmed().toUpper(), chunk.mid(eq + 1).trimmed());
  }

  static const QHash<QString, RRule::Freq> kFreqs = {{QStringLiteral("DAILY"), RRule::Daily},
                                                     {QStringLiteral("WEEKLY"), RRule::Weekly},
                                                     {QStringLiteral("MONTHLY"), RRule::Monthly},
                                                     {QStringLiteral("YEARLY"), RRule::Yearly}};
  const QString freqText = parts.value(QStringLiteral("FREQ")).toUpper();
  const auto freqIt = kFreqs.constFind(freqText);
  if(freqIt == kFreqs.constEnd()) {
    return fail(freqText.isEmpty() ? QStringLiteral("no FREQ") : QStringLiteral("FREQ=%1 is not supported").arg(freqText));
  }
  rule.freq = *freqIt;

  static const QSet<QString> kKnown = {QStringLiteral("FREQ"),
                                       QStringLiteral("INTERVAL"),
                                       QStringLiteral("COUNT"),
                                       QStringLiteral("UNTIL"),
                                       QStringLiteral("BYDAY"),
                                       QStringLiteral("BYMONTHDAY"),
                                       QStringLiteral("BYMONTH"),
                                       QStringLiteral("BYSETPOS"),
                                       QStringLiteral("WKST")};
  for(auto it = parts.constBegin(); it != parts.constEnd(); ++it) {
    if(!kKnown.contains(it.key()) && !it.key().startsWith(QLatin1String("X-"))) {
      return fail(QStringLiteral("%1 is not supported").arg(it.key()));
    }
  }

  if(parts.contains(QStringLiteral("INTERVAL"))) {
    bool ok = false;
    const int n = parts.value(QStringLiteral("INTERVAL")).toInt(&ok);
    if(!ok || n < 1) {
      return fail(QStringLiteral("bad INTERVAL"));
    }
    rule.interval = n;
  }

  if(parts.contains(QStringLiteral("BYDAY"))) {
    for(const QString& token : parts.value(QStringLiteral("BYDAY")).split(QChar(','), Qt::SkipEmptyParts)) {
      const WeekdayNum w = detail::parseWeekdayNum(token);
      if(w.day == 0) {
        return fail(QStringLiteral("bad BYDAY \"%1\"").arg(token));
      }
      // The RFC allows an ordinal only where there is a month or a year for
      // it to count within. "The second Thursday" of a week means nothing.
      if(w.ord != 0 && (rule.freq == RRule::Daily || rule.freq == RRule::Weekly)) {
        return fail(QStringLiteral("an ordinal BYDAY needs FREQ=MONTHLY or YEARLY"));
      }
      if(!rule.byDay.contains(w)) {
        rule.byDay.append(w);
      }
    }
    if(rule.byDay.isEmpty()) {
      return fail(QStringLiteral("empty BYDAY"));
    }
    std::sort(rule.byDay.begin(), rule.byDay.end(), [](const WeekdayNum& a, const WeekdayNum& b) {
      return a.ord != b.ord ? a.ord < b.ord : a.day < b.day;
    });
  }

  if(parts.contains(QStringLiteral("BYMONTHDAY"))) {
    if(rule.freq == RRule::Weekly) {
      return fail(QStringLiteral("BYMONTHDAY cannot be used with FREQ=WEEKLY"));
    }
    if(!detail::parseIntList(parts.value(QStringLiteral("BYMONTHDAY")), -31, 31, &rule.byMonthDay)) {
      return fail(QStringLiteral("bad BYMONTHDAY"));
    }
  }
  if(parts.contains(QStringLiteral("BYMONTH"))) {
    if(!detail::parseIntList(parts.value(QStringLiteral("BYMONTH")), 1, 12, &rule.byMonth)) {
      return fail(QStringLiteral("bad BYMONTH"));
    }
  }
  if(parts.contains(QStringLiteral("BYSETPOS"))) {
    if(!detail::parseIntList(parts.value(QStringLiteral("BYSETPOS")), -366, 366, &rule.bySetPos)) {
      return fail(QStringLiteral("bad BYSETPOS"));
    }
    // BYSETPOS picks from a set some other BYxxx built; on its own it has
    // nothing to pick from.
    if(rule.byDay.isEmpty() && rule.byMonthDay.isEmpty() && rule.byMonth.isEmpty()) {
      return fail(QStringLiteral("BYSETPOS without another BYxxx part"));
    }
  }
  if(parts.contains(QStringLiteral("WKST"))) {
    const int d = detail::dayNumberFor(parts.value(QStringLiteral("WKST")));
    if(d == 0) {
      return fail(QStringLiteral("bad WKST"));
    }
    rule.wkst = d;
  }

  if(parts.contains(QStringLiteral("COUNT"))) {
    bool ok = false;
    const int n = parts.value(QStringLiteral("COUNT")).toInt(&ok);
    if(!ok || n < 1) {
      return fail(QStringLiteral("bad COUNT"));
    }
    rule.count = n;
  }

  if(parts.contains(QStringLiteral("UNTIL"))) {
    const QString raw = parts.value(QStringLiteral("UNTIL")).trimmed().toUpper();
    const QDate d = QDate::fromString(raw.left(8), QStringLiteral("yyyyMMdd"));
    if(!d.isValid()) {
      return fail(QStringLiteral("bad UNTIL"));
    }
    rule.until = d;
    if(raw.size() >= 15 && raw.at(8) == QLatin1Char('T') && raw.endsWith(QLatin1Char('Z'))) {
      const QTime t = QTime::fromString(raw.mid(9, 6), QStringLiteral("HHmmss"));
      if(t.isValid()) {
        // An exact instant. In UTC the date may be a day ahead of the
        // event's own — Google ends a series at 23:59:59 local, written as
        // the next day in UTC — so the day bound is loosened by one and the
        // instant decides.
        rule.untilAt = QDateTime(d, t, QTimeZone::utc());
        rule.until = d.addDays(1);
      }
    }
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
  const auto joinInts = [](const QVector<int>& xs) {
    QStringList s;
    for(const int x : xs) {
      s << QString::number(x);
    }
    return s.join(QChar(','));
  };
  QStringList parts{QStringLiteral("FREQ=") + kNames.value(rule.freq)};
  if(rule.interval > 1) {
    parts << QStringLiteral("INTERVAL=") + QString::number(rule.interval);
  }
  if(!rule.byMonth.isEmpty()) {
    parts << QStringLiteral("BYMONTH=") + joinInts(rule.byMonth);
  }
  if(!rule.byMonthDay.isEmpty()) {
    parts << QStringLiteral("BYMONTHDAY=") + joinInts(rule.byMonthDay);
  }
  if(!rule.byDay.isEmpty()) {
    QStringList days;
    for(const WeekdayNum& w : rule.byDay) {
      days << (w.ord != 0 ? QString::number(w.ord) : QString()) + detail::dayToken(w.day);
    }
    parts << QStringLiteral("BYDAY=") + days.join(QChar(','));
  }
  if(!rule.bySetPos.isEmpty()) {
    parts << QStringLiteral("BYSETPOS=") + joinInts(rule.bySetPos);
  }
  if(rule.wkst != 1) {
    parts << QStringLiteral("WKST=") + detail::dayToken(rule.wkst);
  }
  if(rule.count > 0) {
    parts << QStringLiteral("COUNT=") + QString::number(rule.count);
  }
  if(rule.untilAt.isValid()) {
    parts << QStringLiteral("UNTIL=") + rule.untilAt.toUTC().toString(QStringLiteral("yyyyMMdd'T'HHmmss'Z'"));
  } else if(rule.until.isValid()) {
    parts << QStringLiteral("UNTIL=") + rule.until.toString(QStringLiteral("yyyyMMdd"));
  }
  return parts.join(QChar(';'));
}

namespace detail {

// Every date in [first, last] whose weekday matches `w`, honouring an
// ordinal relative to that span (a month or a year).
inline void weekdaysIn(const QDate& first, const QDate& last, const WeekdayNum& w, QVector<QDate>* out) {
  QVector<QDate> all;
  QDate d = first.addDays((w.day - first.dayOfWeek() + 7) % 7);
  for(; d <= last; d = d.addDays(7)) {
    all.append(d);
  }
  if(w.ord == 0) {
    *out += all;
  } else if(w.ord > 0 && w.ord <= all.size()) {
    out->append(all.at(w.ord - 1));
  } else if(w.ord < 0 && -w.ord <= all.size()) {
    out->append(all.at(all.size() + w.ord));
  }
}

inline bool monthDayMatches(const QDate& d, const QVector<int>& days) {
  if(days.isEmpty()) {
    return true;
  }
  const int fromEnd = d.day() - d.daysInMonth() - 1;  // -1 on the last day
  return days.contains(d.day()) || days.contains(fromEnd);
}

inline bool weekdayMatches(const QDate& d, const QVector<WeekdayNum>& days) {
  if(days.isEmpty()) {
    return true;
  }
  for(const WeekdayNum& w : days) {
    if(w.ord == 0 && w.day == d.dayOfWeek()) {
      return true;
    }
  }
  return false;
}

// The candidate days one month contributes, before BYSETPOS.
inline QVector<QDate> monthCandidates(const RRule& rule, int year, int month, const QDate& start) {
  QVector<QDate> out;
  const QDate first(year, month, 1);
  if(!first.isValid()) {
    return out;
  }
  const QDate last(year, month, first.daysInMonth());
  if(!rule.byMonthDay.isEmpty()) {
    for(const int md : rule.byMonthDay) {
      const int day = md > 0 ? md : first.daysInMonth() + md + 1;
      const QDate d(year, month, day);
      // A day the month does not have is skipped, not clamped.
      if(md <= first.daysInMonth() && md >= -first.daysInMonth() && d.isValid() && weekdayMatches(d, rule.byDay)) {
        out.append(d);
      }
    }
    // An ordinal weekday together with BYMONTHDAY is an intersection; the
    // plain-weekday case was already filtered above.
    bool anyOrd = false;
    for(const WeekdayNum& w : rule.byDay) {
      anyOrd = anyOrd || w.ord != 0;
    }
    if(anyOrd) {
      QVector<QDate> ord;
      for(const WeekdayNum& w : rule.byDay) {
        weekdaysIn(first, last, w, &ord);
      }
      QVector<QDate> both;
      for(const int md : rule.byMonthDay) {
        const int day = md > 0 ? md : first.daysInMonth() + md + 1;
        const QDate d(year, month, day);
        if(d.isValid() && ord.contains(d) && !both.contains(d)) {
          both.append(d);
        }
      }
      out = both;
    }
  } else if(!rule.byDay.isEmpty()) {
    for(const WeekdayNum& w : rule.byDay) {
      weekdaysIn(first, last, w, &out);
    }
  } else {
    // The day comes from DTSTART rather than from the rule, and there the
    // short month clamps: "monthly, from the 31st" lands on the 30th in April
    // and returns to the 31st in May, which is what Outlook does and what
    // heap has always done (audit S9). A rule that names the day itself —
    // BYMONTHDAY=31 — means exactly that day and skips a month without one.
    out.append(QDate(year, month, std::min(start.day(), first.daysInMonth())));
  }
  return out;
}

inline QVector<QDate> applySetPos(QVector<QDate> set, const QVector<int>& positions) {
  std::sort(set.begin(), set.end());
  set.erase(std::unique(set.begin(), set.end()), set.end());
  if(positions.isEmpty()) {
    return set;
  }
  QVector<QDate> out;
  const int n = static_cast<int>(set.size());
  for(const int p : positions) {
    const int i = p > 0 ? p - 1 : n + p;
    if(i >= 0 && i < n && !out.contains(set.at(i))) {
      out.append(set.at(i));
    }
  }
  std::sort(out.begin(), out.end());
  return out;
}

// The sorted, BYSETPOS-applied occurrences of period `p` of the rule.
inline QVector<QDate> periodDates(const RRule& rule, const QDate& start, qint64 p) {
  QVector<QDate> set;
  const qint64 step = p * rule.interval;
  switch(rule.freq) {
    case RRule::Daily: {
      const QDate d = start.addDays(step);
      if((rule.byMonth.isEmpty() || rule.byMonth.contains(d.month())) && monthDayMatches(d, rule.byMonthDay) &&
         weekdayMatches(d, rule.byDay)) {
        set.append(d);
      }
      break;
    }
    case RRule::Weekly: {
      // Weeks are counted from the week the series starts in, where a week
      // begins on WKST — so INTERVAL=2 means every other week of the series,
      // and WKST=SU pairs Sunday with the days after it, not before.
      const int back = (start.dayOfWeek() - rule.wkst + 7) % 7;
      const QDate weekStart = start.addDays(-back).addDays(7 * step);
      QVector<int> days = rule.plainDays();
      if(days.isEmpty()) {
        days.append(start.dayOfWeek());
      }
      for(int i = 0; i < 7; ++i) {
        const QDate d = weekStart.addDays(i);
        if(days.contains(d.dayOfWeek()) && (rule.byMonth.isEmpty() || rule.byMonth.contains(d.month()))) {
          set.append(d);
        }
      }
      break;
    }
    case RRule::Monthly: {
      const QDate m = QDate(start.year(), start.month(), 1).addMonths(static_cast<int>(step));
      if(rule.byMonth.isEmpty() || rule.byMonth.contains(m.month())) {
        set = monthCandidates(rule, m.year(), m.month(), start);
      }
      break;
    }
    case RRule::Yearly: {
      const int year = start.year() + static_cast<int>(step);
      if(!rule.byMonth.isEmpty()) {
        for(const int month : rule.byMonth) {
          set += monthCandidates(rule, year, month, start);
        }
      } else if(!rule.byMonthDay.isEmpty()) {
        for(int month = 1; month <= 12; ++month) {
          set += monthCandidates(rule, year, month, start);
        }
      } else if(!rule.byDay.isEmpty()) {
        // An ordinal counts within the whole year here ("20MO").
        const QDate first(year, 1, 1);
        const QDate last(year, 12, 31);
        for(const WeekdayNum& w : rule.byDay) {
          weekdaysIn(first, last, w, &set);
        }
      } else {
        // Clamped like the monthly case: a birthday on Feb 29 is on the 28th
        // in the other three years, not missing from them.
        const QDate firstOfMonth(year, start.month(), 1);
        set.append(QDate(year, start.month(), std::min(start.day(), firstOfMonth.daysInMonth())));
      }
      break;
    }
    default:
      break;
  }
  return applySetPos(set, rule.bySetPos);
}

// The first period that can reach `from`. Used only when COUNT is not set:
// with a count, every period from the start has to be walked to know which
// occurrence is which.
inline qint64 firstPeriodNear(const RRule& rule, const QDate& start, const QDate& from) {
  if(from <= start) {
    return 0;
  }
  qint64 units = 0;
  switch(rule.freq) {
    case RRule::Daily:
      units = start.daysTo(from);
      break;
    case RRule::Weekly:
      units = start.daysTo(from) / 7;
      break;
    case RRule::Monthly:
      units = (qint64(from.year()) - start.year()) * 12 + (from.month() - start.month());
      break;
    case RRule::Yearly:
      units = from.year() - start.year();
      break;
    default:
      break;
  }
  return std::max<qint64>(0, units / rule.interval - 1);
}

}  // namespace detail

// Every occurrence of `rule` starting at `start` that falls within [from, to].
//
// COUNT is counted from the start of the series, not from `from` — the tenth
// occurrence is the tenth whatever window is being looked at, otherwise
// scrolling the calendar would change how many there are.
//
// A window far from the start costs nothing for an unbounded rule: the walk
// jumps straight to the period that reaches it. The walk is still bounded, so
// a rule that can never match (BYMONTH=2;BYMONTHDAY=30) does not spin.
inline QVector<QDate> expand(const RRule& rule, const QDate& start, const QDate& from, const QDate& to) {
  QVector<QDate> out;
  if(!rule.isValid() || !start.isValid() || !from.isValid() || !to.isValid() || to < from) {
    return out;
  }

  const QDate hardEnd = rule.until.isValid() ? std::min(to, rule.until) : to;
  if(hardEnd < start) {
    return out;
  }

  int emitted = 0;
  const auto take = [&](const QDate& d) {
    ++emitted;
    if(rule.count > 0 && emitted > rule.count) {
      return false;
    }
    if(d >= from && d <= hardEnd) {
      out.append(d);
    }
    return true;
  };

  // DTSTART is the first occurrence whatever the rule says about its day.
  const qint64 firstPeriod = rule.count > 0 ? 0 : detail::firstPeriodNear(rule, start, from);
  if(firstPeriod == 0) {
    if(!take(start)) {
      return out;
    }
  }

  // A guard, not a correctness bound: a century of daily periods.
  constexpr qint64 kMaxPeriods = 40000;
  for(qint64 p = firstPeriod; p < firstPeriod + kMaxPeriods; ++p) {
    const QVector<QDate> dates = detail::periodDates(rule, start, p);
    // The period's own start, to know when the walk has passed the window
    // even in a period that produced nothing.
    QDate periodFloor;
    switch(rule.freq) {
      case RRule::Daily:
        periodFloor = start.addDays(p * rule.interval);
        break;
      case RRule::Weekly:
        periodFloor = start.addDays(-((start.dayOfWeek() - rule.wkst + 7) % 7) + 7 * p * rule.interval);
        break;
      case RRule::Monthly:
        periodFloor = QDate(start.year(), start.month(), 1).addMonths(static_cast<int>(p * rule.interval));
        break;
      case RRule::Yearly:
        periodFloor = QDate(start.year() + static_cast<int>(p * rule.interval), 1, 1);
        break;
      default:
        return out;
    }
    if(!periodFloor.isValid() || periodFloor > hardEnd) {
      break;
    }
    for(const QDate& d : dates) {
      if(d <= start) {
        continue;  // before the series, or DTSTART itself (already taken)
      }
      if(d > hardEnd) {
        return out;
      }
      if(!take(d)) {
        return out;
      }
    }
  }
  return out;
}

// The first day on or after `from` that the rule's own days produce for a
// series starting on `start`, or an invalid date when there is none before the
// series ends. Unlike expand(), DTSTART gets no special treatment: this is the
// question "where should a series created on `from` really begin?". A weekly
// Tue/Thu meeting created by a click on Monday starts on Tuesday, as in Google
// and Outlook — the RFC would otherwise make that Monday an occurrence too
// (TIME-5, audit 2026-09-30).
inline QDate firstRuleDay(RRule rule, const QDate& start, const QDate& from) {
  if(!rule.isValid() || !start.isValid() || !from.isValid()) {
    return {};
  }
  rule.count = 0;
  // The same guard expand() walks under.
  constexpr qint64 kMaxPeriods = 40000;
  for(qint64 p = 0; p < kMaxPeriods; ++p) {
    for(const QDate& d : detail::periodDates(rule, start, p)) {
      if(d < from) {
        continue;
      }
      if(rule.until.isValid() && d > rule.until) {
        return {};
      }
      return d;
    }
  }
  return {};
}

// The first occurrence strictly after `after`, or an invalid date when the
// series has ended. Used where only "the next one" is wanted.
inline QDate nextAfter(const RRule& rule, const QDate& start, const QDate& after) {
  if(!rule.isValid() || !start.isValid() || !after.isValid()) {
    return {};
  }
  // A year is enough for every frequency except a long INTERVAL on YEARLY or
  // a rare BYxxx combination, which are handled by widening.
  for(const int years : {1, 4, 30}) {
    const QVector<QDate> dates = expand(rule, start, after.addDays(1), after.addYears(years));
    if(!dates.isEmpty()) {
      return dates.first();
    }
  }
  return {};
}

}  // namespace heap::cal
