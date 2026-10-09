#pragma once

#include "EventSpan.h"
#include "EventZone.h"
#include "Models.h"
#include "RRule.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QSet>
#include <QStringList>
#include <QTimeZone>
#include <QUuid>

// Reading and writing .ics.
//
// A calendar that cannot be handed a file is a calendar people keep somewhere
// else as well. Every meeting heap holds arrives from Google, Outlook or a
// conference's "add to calendar" link, and the only thing all of them agree on
// is RFC 5545.
//
// The format has a small number of traps that are worth naming, because each
// one is a class of bug that looks like data loss to the user:
//
//   * A long line is folded, and a continuation begins with one space or tab.
//     Unfolding has to happen before anything is parsed, or a long SUMMARY
//     turns into a line nobody recognises.
//   * DTEND for an all-day event is EXCLUSIVE. A three-day trip is written as
//     DTSTART 21, DTEND 24. Reading that as an inclusive end makes every
//     imported all-day event one day too long, and writing an inclusive end
//     makes every exported one a day too short somewhere else.
//   * A timed DTEND may be on the following day. That is an event that crosses
//     midnight, not a broken one.
//   * A VEVENT can contain a VALARM, so the first END: line is not necessarily
//     the end of the event.
//
//   * A time is only as good as its zone. Outlook writes Windows zone names
//     ("Eastern Standard Time"), others invent names and describe the zone in
//     a VTIMEZONE block. Both are resolved; a series keeps its source zone so
//     its occurrences follow that zone's DST (see src/cal/EventZone.h).
//
// Recurrence is handed to src/cal/RRule.h rather than parsed again here, and a
// rule that engine does not model is reported and the event imported as a
// single occurrence — dropping it would hide something the user put in their
// calendar.
namespace heap::cal {

struct IcsImport {
  QVector<CalEvent> events;
  // VEVENTs that could not be read at all: no start, or cancelled.
  int skipped = 0;

  // Occurrences a calendar cancelled (RECURRENCE-ID + STATUS:CANCELLED) of a
  // series this file does not carry: the importer deletes them from the
  // stored series of that id. One whose series is in the file is already an
  // EXDATE on it (TIME-9, audit 2026-09-30).
  struct Cancelled {
    QString masterId;
    QDate date;  // in the series' own clock, like an EXDATE
  };

  QVector<Cancelled> cancelled;
  // One line per thing that was degraded rather than lost.
  QStringList warnings;
  // False when the text had no VCALENDAR or VEVENT at all — not a calendar,
  // which is an error to report, not "0 imported".
  bool recognised = false;
};

namespace detail {

// RFC 5545 folds long lines; a continuation begins with a space or a tab, and
// that one character is not part of the value. Both CRLF and bare LF appear in
// the wild.
inline QStringList unfold(const QString& text) {
  QStringList out;
  const QStringList raw = QString(text).replace(QLatin1String("\r\n"), QLatin1String("\n")).split(QLatin1Char('\n'));
  for(const QString& line : raw) {
    if(!line.isEmpty() && (line.startsWith(QLatin1Char(' ')) || line.startsWith(QLatin1Char('\t'))) && !out.isEmpty()) {
      out.last() += line.mid(1);
    } else {
      out.append(line);
    }
  }
  return out;
}

inline QString unescapeText(const QString& in) {
  QString out;
  out.reserve(in.size());
  for(int i = 0; i < in.size(); ++i) {
    if(in.at(i) != QLatin1Char('\\') || i + 1 >= in.size()) {
      out.append(in.at(i));
      continue;
    }
    const QChar next = in.at(i + 1);
    ++i;
    if(next == QLatin1Char('n') || next == QLatin1Char('N')) {
      out.append(QLatin1Char('\n'));
    } else {
      // ",", ";" and "\" are the escapes the spec defines; anything else was
      // not really an escape, so the character stands for itself.
      out.append(next);
    }
  }
  return out;
}

inline QString escapeText(const QString& in) {
  QString out;
  out.reserve(in.size() + 8);
  for(const QChar c : in) {
    if(c == QLatin1Char('\\')) {
      out += QLatin1String("\\\\");
    } else if(c == QLatin1Char(';')) {
      out += QLatin1String("\\;");
    } else if(c == QLatin1Char(',')) {
      out += QLatin1String("\\,");
    } else if(c == QLatin1Char('\n')) {
      out += QLatin1String("\\n");
    } else if(c != QLatin1Char('\r')) {
      out += c;
    }
  }
  return out;
}

// A content line is NAME;PARAM=V;PARAM=V:VALUE. The first colon that is not
// inside a quoted parameter ends the name-and-parameters part.
struct ContentLine {
  QString name;
  QMap<QString, QString> params;
  QString value;
};

inline ContentLine parseLine(const QString& line) {
  ContentLine out;
  bool quoted = false;
  int colon = -1;
  for(int i = 0; i < line.size(); ++i) {
    const QChar c = line.at(i);
    if(c == QLatin1Char('"')) {
      quoted = !quoted;
    } else if(c == QLatin1Char(':') && !quoted) {
      colon = i;
      break;
    }
  }
  if(colon < 0) {
    out.name = line.trimmed().toUpper();
    return out;
  }
  out.value = line.mid(colon + 1);

  const QString head = line.left(colon);
  const QStringList parts = head.split(QLatin1Char(';'));
  out.name = parts.value(0).trimmed().toUpper();
  for(int i = 1; i < parts.size(); ++i) {
    const int eq = parts.at(i).indexOf(QLatin1Char('='));
    if(eq <= 0) {
      continue;
    }
    QString v = parts.at(i).mid(eq + 1).trimmed();
    if(v.startsWith(QLatin1Char('"')) && v.endsWith(QLatin1Char('"')) && v.size() >= 2) {
      v = v.mid(1, v.size() - 2);
    }
    out.params.insert(parts.at(i).left(eq).trimmed().toUpper(), v);
  }
  return out;
}

// A DATE or DATE-TIME value as written: the wall clock plus whatever says
// which clock it is — a trailing Z, a TZID, or nothing (floating). Resolving
// it to an instant needs the file's VTIMEZONEs, so it is deferred.
struct Instant {
  QDate date;
  QTime time;
  bool dateOnly = false;
  bool utc = false;
  QString tzid;
  bool valid = false;
};

inline Instant parseInstant(const ContentLine& line) {
  Instant out;
  const QString v = line.value.trimmed();
  if(v.size() < 8) {
    return out;
  }
  const QDate d = QDate::fromString(v.left(8), QStringLiteral("yyyyMMdd"));
  if(!d.isValid()) {
    return out;
  }
  out.date = d;
  out.valid = true;

  if(line.params.value(QStringLiteral("VALUE")).compare(QLatin1String("DATE"), Qt::CaseInsensitive) == 0 || v.size() < 15) {
    out.dateOnly = true;
    return out;
  }
  const QTime t = QTime::fromString(v.mid(9, 6), QStringLiteral("HHmmss"));
  if(!t.isValid()) {
    out.dateOnly = true;
    return out;
  }
  out.time = t;
  out.utc = v.endsWith(QLatin1Char('Z'));
  if(!out.utc) {
    out.tzid = line.params.value(QStringLiteral("TZID"));
  }
  return out;
}

// "+0530" / "-0400" / "+013045" → seconds east of UTC.
inline bool parseUtcOffset(const QString& raw, int* seconds) {
  const QString s = raw.trimmed();
  if(s.size() < 5 || (s.at(0) != QLatin1Char('+') && s.at(0) != QLatin1Char('-'))) {
    return false;
  }
  bool okH = false;
  bool okM = false;
  const int h = s.mid(1, 2).toInt(&okH);
  const int m = s.mid(3, 2).toInt(&okM);
  if(!okH || !okM) {
    return false;
  }
  const int sec = s.size() >= 7 ? s.mid(5, 2).toInt() : 0;
  *seconds = (s.at(0) == QLatin1Char('-') ? -1 : 1) * ((h * 3600) + (m * 60) + sec);
  return true;
}

inline QString formatUtcOffset(int seconds) {
  const QChar sign = seconds < 0 ? QLatin1Char('-') : QLatin1Char('+');
  const int a = std::abs(seconds);
  return QString(sign) + QStringLiteral("%1%2").arg(a / 3600, 2, 10, QLatin1Char('0')).arg((a % 3600) / 60, 2, 10, QLatin1Char('0'));
}

// A VTIMEZONE: the file's own description of a zone. Outlook names zones
// "Eastern Standard Time" or "Customized Time Zone", and some exporters invent
// names outright; the offsets inside the block are then all there is to go on.
struct VTimezone {
  struct Onset {
    QDate date;  // DTSTART, the first onset, in the "from" offset's wall clock
    QTime time;
    int offsetFrom = 0;
    int offsetTo = 0;
    RRule rule;             // yearly repetition of the onset, if any
    QVector<QDate> rdates;  // one-off onsets
  };

  QString tzid;
  QVector<Onset> onsets;

  // The UTC offset in force at a wall-clock time of this zone.
  int offsetAt(const QDate& d, const QTime& t) const {
    const QDateTime wall(d, t, QTimeZone::utc());  // naive: compared as walls
    QDateTime bestAt;
    int best = onsets.isEmpty() ? 0 : onsets.first().offsetFrom;
    QDateTime earliest;
    for(const Onset& o : onsets) {
      QVector<QDate> dates = o.rdates;
      if(o.rule.isValid()) {
        dates += expand(o.rule, o.date, QDate(d.year() - 1, 1, 1), QDate(d.year(), 12, 31));
      } else {
        dates.append(o.date);
      }
      for(const QDate& od : dates) {
        const QDateTime at(od, o.time, QTimeZone::utc());
        if(!earliest.isValid() || at < earliest) {
          earliest = at;
          if(!bestAt.isValid()) {
            best = o.offsetFrom;
          }
        }
        if(at <= wall && (!bestAt.isValid() || at > bestAt)) {
          bestAt = at;
          best = o.offsetTo;
        }
      }
    }
    return best;
  }

  QDateTime instantOf(const QDate& d, const QTime& t) const {
    return QDateTime(d, t, QTimeZone::utc()).addSecs(-offsetAt(d, t));
  }
};

// A real zone whose offsets agree with the VTIMEZONE across `year`, so a
// series can keep following that zone's DST in later years. Checked at two
// instants a month; the first zone that matches everywhere wins.
inline QTimeZone matchZone(const VTimezone& vtz, int year) {
  if(vtz.onsets.isEmpty()) {
    return {};
  }
  QVector<QPair<QDateTime, int>> samples;
  for(int month = 1; month <= 12; ++month) {
    for(const int day : {3, 20}) {
      const QDate d(year, month, day);
      const QDateTime at = vtz.instantOf(d, QTime(12, 0));
      samples.append({at, vtz.offsetAt(d, QTime(12, 0))});
    }
  }
  static QHash<QString, QByteArray> cache;
  QString key = QString::number(year);
  for(const auto& s : samples) {
    key += QLatin1Char(',') + QString::number(s.second);
  }
  const auto hit = cache.constFind(key);
  if(hit != cache.constEnd()) {
    return hit->isEmpty() ? QTimeZone() : QTimeZone(*hit);
  }
  const QByteArray hint = QTimeZone::windowsIdToDefaultIanaId(vtz.tzid.toUtf8());
  // Listed by offset, but which offset a backend files a zone under (its
  // standard one, or the one in force today) varies, so every offset the
  // block uses is asked for.
  QList<QByteArray> ids;
  if(!hint.isEmpty()) {
    ids.append(hint);
  }
  QSet<int> offsets;
  for(const auto& s : samples) {
    offsets.insert(s.second);
  }
  for(const int off : offsets) {
    for(const QByteArray& id : QTimeZone::availableTimeZoneIds(off)) {
      if(!ids.contains(id)) {
        ids.append(id);
      }
    }
  }
  // Some backends list only a handful of zones per offset; the rest are
  // tried after them. Once per unknown zone per file, and cached.
  for(const QByteArray& id : QTimeZone::availableTimeZoneIds()) {
    if(!ids.contains(id)) {
      ids.append(id);
    }
  }
  for(const QByteArray& id : ids) {
    const QTimeZone z(id);
    if(!z.isValid()) {
      continue;
    }
    bool all = true;
    for(const auto& s : samples) {
      if(z.offsetFromUtc(s.first) != s.second) {
        all = false;
        break;
      }
    }
    if(all) {
      cache.insert(key, id);
      return z;
    }
  }
  cache.insert(key, QByteArray());
  return {};
}

// A TZID as a real zone: an IANA name, a Windows name ("Eastern Standard
// Time", what Outlook writes), a path-prefixed IANA name
// ("/freeassociation.sourceforge.net/Europe/Berlin"), or — failing all of
// those — the IANA zone whose offsets match the file's own VTIMEZONE.
inline QTimeZone resolveZone(const QString& tzid, const QHash<QString, VTimezone>& vtz, int year) {
  if(tzid.isEmpty()) {
    return {};
  }
  const QTimeZone direct(tzid.toUtf8());
  if(direct.isValid()) {
    return direct;
  }
  const QByteArray win = QTimeZone::windowsIdToDefaultIanaId(tzid.trimmed().toUtf8());
  if(!win.isEmpty()) {
    const QTimeZone z(win);
    if(z.isValid()) {
      return z;
    }
  }
  const QStringList pieces = tzid.split(QLatin1Char('/'), Qt::SkipEmptyParts);
  for(int i = 1; i < pieces.size(); ++i) {
    const QTimeZone z(pieces.mid(i).join(QLatin1Char('/')).toUtf8());
    if(z.isValid()) {
      return z;
    }
  }
  const auto it = vtz.constFind(tzid);
  if(it != vtz.constEnd()) {
    return matchZone(*it, year);
  }
  return {};
}

// The instant a written value stands for. `floatingZone` is the zone a
// floating value is read in — the viewer's. An unknown TZID with a VTIMEZONE
// is resolved through the block's offsets; one with neither floats.
inline QDateTime instantFor(const Instant& in,
                            const QHash<QString, VTimezone>& vtz,
                            const QTimeZone& floatingZone,
                            bool* unknownZone = nullptr) {
  if(in.utc) {
    return QDateTime(in.date, in.time, QTimeZone::utc());
  }
  if(!in.tzid.isEmpty()) {
    const QTimeZone z = resolveZone(in.tzid, vtz, in.date.year());
    if(z.isValid()) {
      return QDateTime(in.date, in.time, z);
    }
    const auto it = vtz.constFind(in.tzid);
    if(it != vtz.constEnd() && !it->onsets.isEmpty()) {
      return it->instantOf(in.date, in.time);
    }
    if(unknownZone != nullptr) {
      *unknownZone = true;
    }
  }
  return QDateTime(in.date, in.time, floatingZone);
}

inline double hourOf(const QTime& t) {
  return t.hour() + (t.minute() / 60.0) + (t.second() / 3600.0);
}

// An ISO 8601 duration, to the extent a calendar uses one: P[n]DT[n]H[n]M[n]S.
// Weeks are accepted too because some exporters write PT0S as P1W.
inline double durationHours(const QString& raw) {
  QString s = raw.trimmed().toUpper();
  if(!s.startsWith(QLatin1Char('P'))) {
    return -1.0;
  }
  s = s.mid(1);
  double hours = 0.0;
  bool inTime = false;
  QString number;
  bool any = false;
  for(const QChar c : s) {
    if(c == QLatin1Char('T')) {
      inTime = true;
      number.clear();
      continue;
    }
    if(c.isDigit()) {
      number.append(c);
      continue;
    }
    const double n = number.toDouble();
    number.clear();
    if(c == QLatin1Char('W')) {
      hours += n * 24.0 * 7.0;
    } else if(c == QLatin1Char('D')) {
      hours += n * 24.0;
    } else if(c == QLatin1Char('H') && inTime) {
      hours += n;
    } else if(c == QLatin1Char('M') && inTime) {
      hours += n / 60.0;
    } else if(c == QLatin1Char('S') && inTime) {
      hours += n / 3600.0;
    } else {
      continue;
    }
    any = true;
  }
  return any ? hours : -1.0;
}

// A VALARM TRIGGER as minutes before the start: "-PT15M" → 15, "PT0S" → 0.
// Anything after the start, relative to the end, or absolute gives -1.
inline int triggerLeadMinutes(const QString& raw) {
  const QString s = raw.trimmed().toUpper();
  if(s.startsWith(QLatin1Char('-'))) {
    const double h = durationHours(s.mid(1));
    return h >= 0.0 ? static_cast<int>(std::lround(h * 60.0)) : -1;
  }
  const double h = durationHours(s.startsWith(QLatin1Char('+')) ? s.mid(1) : s);
  return (h >= 0.0 && h < 1e-9) ? 0 : -1;
}

inline QString foldLine(const QString& line) {
  // 75 octets, per the spec. Measured in UTF-8 bytes, not characters, or a
  // Cyrillic summary folds in the wrong place.
  const QByteArray utf8 = line.toUtf8();
  if(utf8.size() <= 75) {
    return line;
  }
  QString out;
  int used = 0;
  int lineBytes = 0;
  for(const QChar c : line) {
    const int size = QString(c).toUtf8().size();
    if(lineBytes + size > (used == 0 ? 75 : 74)) {
      out += QLatin1String("\r\n ");
      lineBytes = 1;
      used++;
    }
    out += c;
    lineBytes += size;
  }
  return out;
}

inline QString icsDate(const QDate& d) {
  return d.toString(QStringLiteral("yyyyMMdd"));
}

// A wall-clock value. 24:00 is written as midnight of the next day: "T240000"
// is not a legal time, and 23:59 would shorten every event that ends at
// midnight by a minute.
inline QString icsDateTime(const QDate& d, double hour) {
  if(hour >= 24.0 - 1e-9) {
    return icsDate(d.addDays(1)) + QStringLiteral("T000000");
  }
  return icsDate(d) + QStringLiteral("T") + hourToTime(hour).toString(QStringLiteral("HHmmss"));
}

inline QString icsUtc(const QDateTime& at) {
  return at.toUTC().toString(QStringLiteral("yyyyMMdd'T'HHmmss'Z'"));
}

// Names as a calendar writes them: an attendee's CN, or the address when
// there is none. "mailto:" and Apple's "invalid:nomail" are not names.
inline QString attendeeName(const ContentLine& cl) {
  const QString cn = cl.params.value(QStringLiteral("CN")).trimmed();
  if(!cn.isEmpty()) {
    return cn;
  }
  QString v = cl.value.trimmed();
  if(v.startsWith(QLatin1String("mailto:"), Qt::CaseInsensitive)) {
    v = v.mid(7);
  }
  if(v.compare(QLatin1String("invalid:nomail"), Qt::CaseInsensitive) == 0) {
    return {};
  }
  return v;
}

// A VTIMEZONE for `zone`, generated from Qt's own transition data for the
// years in [fromYear, toYear]. Most importers resolve an IANA TZID on their
// own; Outlook insists on the block.
inline QStringList vtimezoneLines(const QTimeZone& zone, int fromYear, int toYear) {
  QStringList out;
  out << QStringLiteral("BEGIN:VTIMEZONE") << QStringLiteral("TZID:") + QString::fromUtf8(zone.id());
  const QDateTime a(QDate(fromYear, 1, 1), QTime(0, 0), QTimeZone::utc());
  const QDateTime b(QDate(toYear + 1, 1, 1), QTime(0, 0), QTimeZone::utc());
  const QTimeZone::OffsetDataList trans = zone.hasTransitions() ? zone.transitions(a, b) : QTimeZone::OffsetDataList();
  if(trans.isEmpty()) {
    const int off = zone.offsetFromUtc(a);
    out << QStringLiteral("BEGIN:STANDARD") << QStringLiteral("DTSTART:19700101T000000")
        << QStringLiteral("TZOFFSETFROM:") + formatUtcOffset(off) << QStringLiteral("TZOFFSETTO:") + formatUtcOffset(off)
        << QStringLiteral("END:STANDARD");
  } else {
    // One component per kind of change, from the first year's transitions,
    // repeated yearly by the weekday-of-month it fell on.
    QSet<bool> seen;
    for(const QTimeZone::OffsetData& t : trans) {
      const bool daylight = t.daylightTimeOffset != 0;
      if(seen.contains(daylight)) {
        continue;
      }
      seen.insert(daylight);
      const int from = zone.offsetFromUtc(t.atUtc.addSecs(-1));
      const QDateTime wall = t.atUtc.addSecs(from).toUTC();  // naive wall in the old offset
      const QDate d = wall.date();
      const int ord = (d.day() + 7 > d.daysInMonth()) ? -1 : ((d.day() - 1) / 7) + 1;
      const QString kind = daylight ? QStringLiteral("DAYLIGHT") : QStringLiteral("STANDARD");
      out << QStringLiteral("BEGIN:") + kind
          << QStringLiteral("DTSTART:") + icsDate(d) + QStringLiteral("T") + wall.time().toString(QStringLiteral("HHmmss"))
          << QStringLiteral("TZOFFSETFROM:") + formatUtcOffset(from) << QStringLiteral("TZOFFSETTO:") + formatUtcOffset(t.offsetFromUtc)
          << QStringLiteral("RRULE:FREQ=YEARLY;BYMONTH=%1;BYDAY=%2%3").arg(d.month()).arg(ord).arg(dayToken(d.dayOfWeek()))
          << QStringLiteral("END:") + kind;
    }
  }
  out << QStringLiteral("END:VTIMEZONE");
  return out;
}

}  // namespace detail

// Reads a document. `display` is the viewer's zone: floating times are read
// in it, and everything that is not kept in its own zone is converted to it.
// `uidDomain` is this install's (see toIcs): a UID ending in it is one of our
// own events coming back and maps to its local id; any other UID is kept whole.
inline IcsImport parseIcs(const QString& text,
                          const QTimeZone& display = QTimeZone::systemTimeZone(),
                          const QString& uidDomain = QString()) {
  IcsImport out;
  const QStringList lines = detail::unfold(text);

  // Pass 1: the file's VTIMEZONEs, wherever they sit, so pass 2 can resolve
  // a TZID no matter the order.
  QHash<QString, detail::VTimezone> zones;
  {
    detail::VTimezone cur;
    detail::VTimezone::Onset onset;
    bool inTz = false;
    bool inOnset = false;
    for(const QString& raw : lines) {
      const QString line = raw.trimmed();
      if(line.isEmpty()) {
        continue;
      }
      const detail::ContentLine cl = detail::parseLine(line);
      const QString v = cl.value.trimmed().toUpper();
      if(cl.name == QLatin1String("BEGIN") && v == QLatin1String("VTIMEZONE")) {
        inTz = true;
        cur = {};
      } else if(inTz && cl.name == QLatin1String("END") && v == QLatin1String("VTIMEZONE")) {
        inTz = false;
        if(!cur.tzid.isEmpty()) {
          zones.insert(cur.tzid, cur);
        }
      } else if(inTz && cl.name == QLatin1String("BEGIN") && (v == QLatin1String("STANDARD") || v == QLatin1String("DAYLIGHT"))) {
        inOnset = true;
        onset = {};
      } else if(inTz && cl.name == QLatin1String("END") && (v == QLatin1String("STANDARD") || v == QLatin1String("DAYLIGHT"))) {
        inOnset = false;
        if(onset.date.isValid()) {
          cur.onsets.append(onset);
        }
      } else if(inTz && !inOnset && cl.name == QLatin1String("TZID")) {
        cur.tzid = cl.value.trimmed();
      } else if(inOnset) {
        if(cl.name == QLatin1String("DTSTART")) {
          const detail::Instant at = detail::parseInstant(cl);
          onset.date = at.date;
          onset.time = at.dateOnly ? QTime(0, 0) : at.time;
        } else if(cl.name == QLatin1String("TZOFFSETFROM")) {
          detail::parseUtcOffset(cl.value, &onset.offsetFrom);
        } else if(cl.name == QLatin1String("TZOFFSETTO")) {
          detail::parseUtcOffset(cl.value, &onset.offsetTo);
        } else if(cl.name == QLatin1String("RRULE")) {
          onset.rule = parseRRule(cl.value);
        } else if(cl.name == QLatin1String("RDATE")) {
          for(const QString& piece : cl.value.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
            const QDate d = QDate::fromString(piece.trimmed().left(8), QStringLiteral("yyyyMMdd"));
            if(d.isValid()) {
              onset.rdates.append(d);
            }
          }
        }
      }
    }
  }

  bool inEvent = false;
  int nesting = 0;  // a VALARM inside a VEVENT must not end it
  bool inAlarm = false;
  QSet<QString> usedIds;
  QSet<QString> warnedZones;

  QString uid;
  QString summary;
  QString location;
  QString description;
  QString url;
  QString heapType;
  QString heapContext;
  QString rrule;
  QStringList attendees;
  QVector<detail::Instant> exdates;
  detail::Instant dtStart;
  detail::Instant dtEnd;
  detail::Instant recurrenceId;
  QString duration;
  QString rawStart;
  int reminder = CalEvent::kReminderDefault;
  QString alarmTrigger;
  bool alarmRelEnd = false;
  bool cancelled = false;

  // Overrides resolve their RECURRENCE-ID against the master's zone, which
  // may come later in the file.
  struct PendingOverride {
    int index;
    detail::Instant recurrenceId;
  };

  QVector<PendingOverride> pending;
  // Cancelled occurrences, by the UID of their series; settled like overrides.
  QVector<QPair<QString, detail::Instant>> cancelledIds;

  const auto reset = [&]() {
    uid.clear();
    summary.clear();
    location.clear();
    description.clear();
    url.clear();
    heapType.clear();
    heapContext.clear();
    rrule.clear();
    attendees.clear();
    exdates.clear();
    dtStart = {};
    dtEnd = {};
    recurrenceId = {};
    duration.clear();
    rawStart.clear();
    reminder = CalEvent::kReminderDefault;
    cancelled = false;
  };

  for(const QString& raw : lines) {
    const QString line = raw.trimmed();
    if(line.isEmpty()) {
      continue;
    }
    const detail::ContentLine cl = detail::parseLine(line);

    if(cl.name == QLatin1String("BEGIN")) {
      const QString kind = cl.value.trimmed().toUpper();
      if(kind == QLatin1String("VCALENDAR")) {
        out.recognised = true;
      }
      if(!inEvent && kind == QLatin1String("VEVENT")) {
        inEvent = true;
        out.recognised = true;
        nesting = 0;
        reset();
      } else if(inEvent) {
        nesting++;
        if(nesting == 1 && kind == QLatin1String("VALARM")) {
          inAlarm = true;
          alarmTrigger.clear();
          alarmRelEnd = false;
        }
      }
      continue;
    }
    if(cl.name == QLatin1String("END")) {
      if(!inEvent) {
        continue;
      }
      if(nesting > 0) {
        if(nesting == 1 && inAlarm) {
          inAlarm = false;
          // The first alarm that fires before the start becomes the event's
          // own reminder lead.
          const int lead = detail::triggerLeadMinutes(alarmTrigger);
          if(reminder == CalEvent::kReminderDefault && !alarmRelEnd && lead >= 0) {
            reminder = lead;
          }
        }
        nesting--;
        continue;
      }
      if(cl.value.trimmed().compare(QLatin1String("VEVENT"), Qt::CaseInsensitive) != 0) {
        continue;
      }
      inEvent = false;

      // A cancelled occurrence of a series is how Google, Outlook and CalDAV
      // delete one meeting of many. It is a deletion, not an event that
      // failed to read: counted as skipped, it left the meeting standing
      // (TIME-9, audit 2026-09-30).
      if(cancelled && recurrenceId.valid && !uid.isEmpty()) {
        cancelledIds.append({uid, recurrenceId});
        continue;
      }
      if(cancelled || !dtStart.valid) {
        out.skipped++;
        continue;
      }

      CalEvent e;
      if(uid.isEmpty()) {
        // Stable, so re-importing a UID-less file updates what the first
        // import brought in instead of duplicating it.
        const QByteArray basis = (summary + QLatin1Char('|') + rawStart + QLatin1Char('|') + duration).toUtf8();
        e.id = QStringLiteral("ics-") + QString::fromLatin1(QCryptographicHash::hash(basis, QCryptographicHash::Sha1).toHex().left(12));
      } else {
        e.id = uid;
      }
      e.title = summary;
      e.type = heapType.isEmpty() ? QStringLiteral("sync") : heapType;
      e.context = heapContext;
      e.location = location;
      e.notes = description;
      e.url = url;
      e.attendees = attendees.join(QStringLiteral(", "));
      e.reminderMinutes = reminder;
      e.allDay = dtStart.dateOnly;

      QString ruleWhy;
      const bool ruleOk = !rrule.isEmpty() && parseRRule(rrule, &ruleWhy).isValid();
      if(!rrule.isEmpty() && !ruleOk) {
        out.warnings << QStringLiteral("Unsupported recurrence rule on \"%1\" (%2: %3): imported as a single event")
                            .arg(e.title.isEmpty() ? e.id : e.title, ruleWhy, rrule);
      }

      QDate endDate;
      double startHour = 0.0;
      double endHour = 24.0;
      QDate startDate = dtStart.date;
      QTimeZone keepZone;  // the zone a series stays in, when it has one

      if(e.allDay) {
        // DTEND is exclusive for a DATE value: 21st to 24th is three days, the
        // last of which is the 23rd. Reading it inclusively makes every
        // imported all-day event a day too long.
        endDate = dtEnd.valid ? dtEnd.date.addDays(-1) : dtStart.date;
        if(!dtEnd.valid && !duration.isEmpty()) {
          const double h = detail::durationHours(duration);
          if(h > 0) {
            endDate = dtStart.date.addDays(static_cast<int>(h / 24.0) - 1);
          }
        }
        if(!endDate.isValid() || endDate < dtStart.date) {
          endDate = dtStart.date;
        }
      } else {
        bool unknown = false;
        const QDateTime startAt = detail::instantFor(dtStart, zones, display, &unknown);
        if(unknown && warnedZones.size() < 5 && !warnedZones.contains(dtStart.tzid)) {
          warnedZones.insert(dtStart.tzid);
          out.warnings << QStringLiteral("Unknown time zone \"%1\": times taken as written").arg(dtStart.tzid);
        }
        QDateTime endAt;
        if(dtEnd.valid) {
          endAt = dtEnd.dateOnly ? QDateTime(dtEnd.date, QTime(0, 0), startAt.timeZone()) : detail::instantFor(dtEnd, zones, display);
        } else if(!duration.isEmpty() && detail::durationHours(duration) > 0) {
          endAt = startAt.addSecs(static_cast<qint64>(std::llround(detail::durationHours(duration) * 3600.0)));
        } else {
          // No end at all: an hour, which is what every calendar defaults to.
          endAt = startAt.addSecs(3600);
        }

        // A series stays in its source zone, so that its DST is the source's.
        // Everything else is converted once, to the viewer's clock.
        if(ruleOk) {
          if(dtStart.utc) {
            keepZone = QTimeZone::utc();
          } else if(!dtStart.tzid.isEmpty()) {
            keepZone = detail::resolveZone(dtStart.tzid, zones, dtStart.date.year());
          }
        }
        const QTimeZone wallZone = keepZone.isValid() ? keepZone : display;
        const QDateTime s = startAt.toTimeZone(wallZone);
        QDateTime en = endAt.toTimeZone(wallZone);
        if(en <= s) {
          en = s.addSecs(3600);
        }
        startDate = s.date();
        startHour = detail::hourOf(s.time());
        endDate = en.date();
        endHour = detail::hourOf(en.time());
        if(endHour <= 0.0 && endDate > startDate) {
          endDate = endDate.addDays(-1);
          endHour = 24.0;
        }
      }

      const Span span = normalizeSpan(startDate, endDate, startHour, endHour, e.allDay, 1.0 / 60.0);
      e.date = span.date;
      e.endDate = (span.endDate == span.date) ? QDate() : span.endDate;
      e.start = span.start;
      e.end = span.end;

      if(ruleOk) {
        e.rrule = rrule;
        if(keepZone.isValid()) {
          e.tz = QString::fromUtf8(keepZone.id());
        }
      }
      // Deleted occurrences are dates in the series' own zone.
      for(const detail::Instant& x : exdates) {
        QDate d = x.date;
        if(!x.dateOnly && !e.allDay) {
          const QDateTime at = detail::instantFor(x, zones, display);
          d = at.toTimeZone(keepZone.isValid() ? keepZone : display).date();
          if(x.tzid.isEmpty() && !x.utc) {
            d = x.date;  // floating, like the series
          }
        }
        if(d.isValid() && !e.exdates.contains(d)) {
          e.exdates.append(d);
        }
      }
      if(recurrenceId.valid) {
        // An override names the occurrence it replaces; the master is the
        // event sharing its UID. The date is settled once the master is known.
        e.originalDate = recurrenceId.date;
        e.masterId = e.id;
        e.id = e.id + QStringLiteral("-") + detail::icsDate(recurrenceId.date);
        pending.append({static_cast<int>(out.events.size()), recurrenceId});
      }
      // Two UID-less events that hash alike are still two events.
      QString unique = e.id;
      for(int n = 2; usedIds.contains(unique); ++n) {
        unique = e.id + QStringLiteral("-") + QString::number(n);
      }
      e.id = unique;
      usedIds.insert(e.id);
      out.events.append(e);
      continue;
    }

    if(!inEvent) {
      continue;
    }
    if(nesting > 0) {
      if(inAlarm && nesting == 1 && cl.name == QLatin1String("TRIGGER")) {
        alarmTrigger = cl.value.trimmed();
        alarmRelEnd = cl.params.value(QStringLiteral("RELATED")).compare(QLatin1String("END"), Qt::CaseInsensitive) == 0 ||
                      cl.params.value(QStringLiteral("VALUE")).compare(QLatin1String("DATE-TIME"), Qt::CaseInsensitive) == 0;
      }
      continue;
    }

    if(cl.name == QLatin1String("UID")) {
      uid = cl.value.trimmed();
      if(!uidDomain.isEmpty() && uid.endsWith(QLatin1Char('@') + uidDomain, Qt::CaseInsensitive)) {
        uid.chop(uidDomain.size() + 1);
      }
    } else if(cl.name == QLatin1String("SUMMARY")) {
      summary = detail::unescapeText(cl.value);
    } else if(cl.name == QLatin1String("LOCATION")) {
      location = detail::unescapeText(cl.value);
    } else if(cl.name == QLatin1String("DESCRIPTION")) {
      description = detail::unescapeText(cl.value);
    } else if(cl.name == QLatin1String("URL")) {
      url = cl.value.trimmed();
    } else if(cl.name == QLatin1String("ATTENDEE")) {
      const QString name = detail::attendeeName(cl);
      if(!name.isEmpty() && !attendees.contains(name)) {
        attendees << name;
      }
    } else if(cl.name == QLatin1String("X-HEAP-TYPE")) {
      heapType = cl.value.trimmed();
    } else if(cl.name == QLatin1String("X-HEAP-CONTEXT")) {
      heapContext = detail::unescapeText(cl.value);
    } else if(cl.name == QLatin1String("DTSTART")) {
      dtStart = detail::parseInstant(cl);
      rawStart = line;
    } else if(cl.name == QLatin1String("DTEND")) {
      dtEnd = detail::parseInstant(cl);
    } else if(cl.name == QLatin1String("DURATION")) {
      duration = cl.value.trimmed();
    } else if(cl.name == QLatin1String("RRULE")) {
      rrule = cl.value.trimmed();
    } else if(cl.name == QLatin1String("RECURRENCE-ID")) {
      recurrenceId = detail::parseInstant(cl);
    } else if(cl.name == QLatin1String("STATUS")) {
      cancelled = cl.value.trimmed().compare(QLatin1String("CANCELLED"), Qt::CaseInsensitive) == 0;
    } else if(cl.name == QLatin1String("EXDATE")) {
      // One line may carry several dates, and several lines may appear.
      for(const QString& piece : cl.value.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
        detail::ContentLine one = cl;
        one.value = piece.trimmed();
        const detail::Instant at = detail::parseInstant(one);
        if(at.valid) {
          exdates.append(at);
        }
      }
    }
  }

  // An unterminated VEVENT is a truncated file, not an event.
  if(inEvent) {
    out.skipped++;
  }

  // Settle each override's occurrence date in its master's zone: a
  // RECURRENCE-ID written in UTC names a date that may not be the series'.
  QHash<QString, int> masters;
  for(int i = 0; i < out.events.size(); ++i) {
    if(out.events.at(i).masterId.isEmpty()) {
      masters.insert(out.events.at(i).id, i);
    }
  }
  for(const PendingOverride& p : pending) {
    CalEvent& ov = out.events[p.index];
    const detail::Instant& rid = p.recurrenceId;
    if(rid.dateOnly || (rid.tzid.isEmpty() && !rid.utc)) {
      continue;  // a date, or floating like the series: taken as written
    }
    const auto it = masters.constFind(ov.masterId);
    const QTimeZone mz = it != masters.constEnd() ? zoneOf(out.events.at(*it)) : QTimeZone();
    const QDateTime at = detail::instantFor(rid, zones, display);
    ov.originalDate = at.toTimeZone(mz.isValid() ? mz : display).date();
  }
  QSet<QString> dropped;
  for(const auto& [masterUid, rid] : std::as_const(cancelledIds)) {
    const auto it = masters.constFind(masterUid);
    QDate day = rid.date;
    if(!rid.dateOnly && (!rid.tzid.isEmpty() || rid.utc)) {
      const QTimeZone mz = it != masters.constEnd() ? zoneOf(out.events.at(*it)) : QTimeZone();
      day = detail::instantFor(rid, zones, display).toTimeZone(mz.isValid() ? mz : display).date();
    }
    if(!day.isValid()) {
      continue;
    }
    if(it == masters.constEnd()) {
      out.cancelled.append({masterUid, day});
      continue;
    }
    CalEvent& m = out.events[*it];
    if(!m.exdates.contains(day)) {
      m.exdates.append(day);
      std::sort(m.exdates.begin(), m.exdates.end());
    }
    dropped.insert(masterUid + QLatin1Char('|') + day.toString(Qt::ISODate));
  }
  // An override of a cancelled occurrence in the same file goes with it.
  // Removed only now: `masters` holds indices into the list.
  if(!dropped.isEmpty()) {
    out.events.removeIf([&](const CalEvent& e) {
      return !e.masterId.isEmpty() && dropped.contains(e.masterId + QLatin1Char('|') + e.originalDate.toString(Qt::ISODate));
    });
  }
  return out;
}

// Writes a document. Floating times are the viewer's (`display`): a single
// event goes out in UTC, which every reader agrees on; a series goes out
// in the viewer's zone by name (with its VTIMEZONE), so its DST keeps working
// wherever it is opened. A series that kept a source zone keeps it.
// `uidDomain` qualifies a local id ("ev-2" → "ev-2@<domain>"): a bare local id
// is the same in every install (the demo's ev-1..ev-5 above all), so another
// heap importing the file took it for its own event and overwrote that
// (TIME-25, audit 2026-09-30). An id that already has an "@" came from some
// calendar's UID and leaves as it arrived.
inline QString toIcs(const QVector<CalEvent>& events,
                     const QTimeZone& display = QTimeZone::systemTimeZone(),
                     const QDateTime& now = QDateTime::currentDateTimeUtc(),
                     const QString& uidDomain = QString()) {
  QStringList body;
  QHash<QByteArray, QPair<int, int>> zoneYears;  // zone id → year range used
  const auto useZone = [&](const QTimeZone& z, const QDate& d) {
    auto it = zoneYears.find(z.id());
    if(it == zoneYears.end()) {
      zoneYears.insert(z.id(), {d.year(), d.year()});
    } else {
      it->first = std::min(it->first, d.year());
      it->second = std::max(it->second, d.year());
    }
  };
  QHash<QString, const CalEvent*> byId;
  for(const CalEvent& e : events) {
    byId.insert(e.id, &e);
  }
  // The zone an event's wall times are written in when it is not UTC.
  const auto seriesZone = [&](const CalEvent& e) -> QTimeZone {
    const QTimeZone z = zoneOf(e);
    if(z.isValid()) {
      return z;
    }
    return e.rrule.isEmpty() ? QTimeZone() : display;
  };
  const auto zoned = [](const QString& prop, const QTimeZone& z, const QDate& d, double h) {
    if(z == QTimeZone::utc() || z.id() == "UTC") {
      return prop + QStringLiteral(":") + detail::icsUtc(wallInstant(d, h, QTimeZone::utc()));
    }
    return prop + QStringLiteral(";TZID=") + QString::fromUtf8(z.id()) + QStringLiteral(":") + detail::icsDateTime(d, h);
  };

  for(const CalEvent& e : events) {
    if(!e.date.isValid()) {
      continue;
    }
    body << QStringLiteral("BEGIN:VEVENT");
    const QString localUid = e.masterId.isEmpty() ? e.id : e.masterId;
    body << QStringLiteral("UID:") +
                (uidDomain.isEmpty() || localUid.contains(QLatin1Char('@')) ? localUid : localUid + QLatin1Char('@') + uidDomain);
    body << QStringLiteral("DTSTAMP:") + detail::icsUtc(now);
    if(!e.title.isEmpty()) {
      body << QStringLiteral("SUMMARY:") + detail::escapeText(e.title);
    }
    if(!e.location.isEmpty()) {
      body << QStringLiteral("LOCATION:") + detail::escapeText(e.location);
    }
    if(!e.notes.isEmpty()) {
      body << QStringLiteral("DESCRIPTION:") + detail::escapeText(e.notes);
    }
    if(!e.url.isEmpty()) {
      body << QStringLiteral("URL:") + e.url;
    }
    if(!e.type.isEmpty()) {
      body << QStringLiteral("X-HEAP-TYPE:") + e.type;
    }
    if(!e.context.isEmpty()) {
      body << QStringLiteral("X-HEAP-CONTEXT:") + detail::escapeText(e.context);
    }
    for(const QString& raw : e.attendees.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
      const QString name = raw.trimmed();
      if(name.isEmpty()) {
        continue;
      }
      // An address when the name is one; otherwise the placeholder Apple
      // uses for a person with no address, which every reader accepts.
      body << (name.contains(QLatin1Char('@'))
                   ? QStringLiteral("ATTENDEE:mailto:") + name
                   : QStringLiteral("ATTENDEE;CN=\"%1\":invalid:nomail").arg(QString(name).remove(QLatin1Char('"'))));
    }

    const QDate last = (e.endDate.isValid() && e.endDate > e.date) ? e.endDate : e.date;
    const QTimeZone z = seriesZone(e);
    if(e.allDay) {
      body << QStringLiteral("DTSTART;VALUE=DATE:") + detail::icsDate(e.date);
      // Exclusive, per the spec: the day after the last one covered.
      body << QStringLiteral("DTEND;VALUE=DATE:") + detail::icsDate(last.addDays(1));
    } else if(z.isValid()) {
      useZone(z, e.date);
      body << zoned(QStringLiteral("DTSTART"), z, e.date, e.start);
      body << zoned(QStringLiteral("DTEND"), z, last, e.end);
    } else {
      body << QStringLiteral("DTSTART:") + detail::icsUtc(wallInstant(e.date, e.start, display));
      body << QStringLiteral("DTEND:") + detail::icsUtc(wallInstant(last, e.end, display));
    }
    if(!e.rrule.isEmpty()) {
      body << QStringLiteral("RRULE:") + e.rrule;
    }
    if(!e.exdates.isEmpty()) {
      QStringList ex;
      for(const QDate& d : e.exdates) {
        if(d.isValid()) {
          ex << (e.allDay ? detail::icsDate(d) : detail::icsDateTime(d, e.start));
        }
      }
      if(!ex.isEmpty()) {
        if(e.allDay) {
          body << QStringLiteral("EXDATE;VALUE=DATE:") + ex.join(QLatin1Char(','));
        } else if(z.isValid() && !(z == QTimeZone::utc())) {
          body << QStringLiteral("EXDATE;TZID=") + QString::fromUtf8(z.id()) + QStringLiteral(":") + ex.join(QLatin1Char(','));
        } else {
          QStringList utc;
          for(const QDate& d : e.exdates) {
            utc << detail::icsUtc(wallInstant(d, e.start, QTimeZone::utc()));
          }
          body << QStringLiteral("EXDATE:") + utc.join(QLatin1Char(','));
        }
      }
    }
    if(e.originalDate.isValid()) {
      // The occurrence being replaced is named by its ORIGINAL start — the
      // master's time on that date — not by where the override moved it.
      const CalEvent* m = byId.value(e.masterId, nullptr);
      const bool allDayMaster = m != nullptr ? m->allDay : e.allDay;
      if(allDayMaster) {
        body << QStringLiteral("RECURRENCE-ID;VALUE=DATE:") + detail::icsDate(e.originalDate);
      } else {
        const double h = m != nullptr ? m->start : e.start;
        const QTimeZone mz = m != nullptr ? seriesZone(*m) : display;
        body << zoned(QStringLiteral("RECURRENCE-ID"), mz.isValid() ? mz : display, e.originalDate, h);
      }
    }
    if(e.reminderMinutes >= 0 && !e.allDay) {
      body << QStringLiteral("BEGIN:VALARM") << QStringLiteral("ACTION:DISPLAY")
           << QStringLiteral("DESCRIPTION:") + detail::escapeText(e.title.isEmpty() ? QStringLiteral("Reminder") : e.title)
           << QStringLiteral("TRIGGER:-PT%1M").arg(e.reminderMinutes) << QStringLiteral("END:VALARM");
    }
    body << QStringLiteral("END:VEVENT");
  }

  QStringList lines;
  lines << QStringLiteral("BEGIN:VCALENDAR") << QStringLiteral("VERSION:2.0") << QStringLiteral("PRODID:-//lowkey//EN")
        << QStringLiteral("CALSCALE:GREGORIAN");
  QList<QByteArray> ids = zoneYears.keys();
  std::sort(ids.begin(), ids.end());
  for(const QByteArray& id : ids) {
    if(id == "UTC") {
      continue;
    }
    const auto years = zoneYears.value(id);
    lines << detail::vtimezoneLines(QTimeZone(id), years.first, years.second);
  }
  lines << body;
  lines << QStringLiteral("END:VCALENDAR");

  QStringList folded;
  folded.reserve(lines.size());
  for(const QString& l : lines) {
    folded << detail::foldLine(l);
  }
  return folded.join(QStringLiteral("\r\n")) + QStringLiteral("\r\n");
}

}  // namespace heap::cal
