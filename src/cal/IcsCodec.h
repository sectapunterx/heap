#pragma once

#include "EventSpan.h"
#include "Models.h"
#include "RRule.h"

#include <QDateTime>
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
// Recurrence is handed to src/cal/RRule.h rather than parsed again here, and a
// rule that engine does not model is reported and the event imported as a
// single occurrence — dropping it would hide something the user put in their
// calendar.
namespace heap::cal {

struct IcsImport {
  QVector<CalEvent> events;
  // VEVENTs that could not be read at all: no start, or cancelled.
  int skipped = 0;
  // One line per thing that was degraded rather than lost.
  QStringList warnings;
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

// A DATE or DATE-TIME value, resolved to local wall-clock time.
struct Instant {
  QDate date;
  QTime time;
  bool dateOnly = false;
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

  if(v.endsWith(QLatin1Char('Z'))) {
    // UTC: shown to the user in their own time, which is the only time heap
    // models. Without this a 14:00Z meeting reads as 14:00 everywhere.
    const QDateTime utc(d, t, QTimeZone::utc());
    const QDateTime local = utc.toLocalTime();
    out.date = local.date();
    out.time = local.time();
    return out;
  }
  const QString tzid = line.params.value(QStringLiteral("TZID"));
  if(!tzid.isEmpty()) {
    const QTimeZone zone(tzid.toUtf8());
    if(zone.isValid()) {
      const QDateTime zoned(d, t, zone);
      const QDateTime local = zoned.toLocalTime();
      out.date = local.date();
      out.time = local.time();
    }
    // An unknown zone falls through as floating local time: better to show the
    // meeting at the hour written down than to drop it.
  }
  return out;
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

inline QString icsDateTime(const QDate& d, double hour) {
  return icsDate(d) + QStringLiteral("T") + hourToTime(hour).toString(QStringLiteral("HHmmss"));
}

}  // namespace detail

inline IcsImport parseIcs(const QString& text) {
  IcsImport out;
  const QStringList lines = detail::unfold(text);

  bool inEvent = false;
  int nesting = 0;  // a VALARM inside a VEVENT must not end it
  int anonymous = 0;
  bool warnedDescription = false;

  QString uid;
  QString summary;
  QString location;
  QString rrule;
  QVector<QDate> exdates;
  detail::Instant dtStart;
  detail::Instant dtEnd;
  detail::Instant recurrenceId;
  QString duration;
  bool cancelled = false;
  bool sawDescription = false;

  const auto reset = [&]() {
    uid.clear();
    summary.clear();
    location.clear();
    rrule.clear();
    exdates.clear();
    dtStart = {};
    dtEnd = {};
    recurrenceId = {};
    duration.clear();
    cancelled = false;
    sawDescription = false;
  };

  for(const QString& raw : lines) {
    const QString line = raw.trimmed();
    if(line.isEmpty()) {
      continue;
    }
    const detail::ContentLine cl = detail::parseLine(line);

    if(cl.name == QLatin1String("BEGIN")) {
      const QString kind = cl.value.trimmed().toUpper();
      if(!inEvent && kind == QLatin1String("VEVENT")) {
        inEvent = true;
        nesting = 0;
        reset();
      } else if(inEvent) {
        nesting++;
      }
      continue;
    }
    if(cl.name == QLatin1String("END")) {
      if(!inEvent) {
        continue;
      }
      if(nesting > 0) {
        nesting--;
        continue;
      }
      if(cl.value.trimmed().compare(QLatin1String("VEVENT"), Qt::CaseInsensitive) != 0) {
        continue;
      }
      inEvent = false;

      if(cancelled || !dtStart.valid) {
        out.skipped++;
        continue;
      }
      if(sawDescription && !warnedDescription) {
        warnedDescription = true;
        out.warnings << QStringLiteral("DESCRIPTION is not stored: heap events carry a title and a context only.");
      }

      CalEvent e;
      e.id = uid.isEmpty() ? QStringLiteral("ics-%1-%2").arg(QUuid::createUuid().toString(QUuid::WithoutBraces).left(8)).arg(anonymous++)
                           : uid;
      e.title = summary;
      e.type = QStringLiteral("sync");
      e.context = location;
      e.allDay = dtStart.dateOnly;

      QDate endDate;
      double startHour = 0.0;
      double endHour = 24.0;

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
        startHour = detail::hourOf(dtStart.time);
        if(dtEnd.valid) {
          endDate = dtEnd.date;
          endHour = dtEnd.dateOnly ? 24.0 : detail::hourOf(dtEnd.time);
        } else if(!duration.isEmpty() && detail::durationHours(duration) > 0) {
          const double h = detail::durationHours(duration);
          const double raw = startHour + h;
          endDate = dtStart.date.addDays(static_cast<int>(raw / 24.0));
          endHour = raw - (24.0 * static_cast<int>(raw / 24.0));
          if(endHour <= 0.0 && endDate > dtStart.date) {
            endDate = endDate.addDays(-1);
            endHour = 24.0;
          }
        } else {
          // No end at all: an hour, which is what every calendar defaults to.
          endDate = dtStart.date;
          endHour = startHour + 1.0;
        }
      }

      const Span span = normalizeSpan(dtStart.date, endDate, startHour, endHour, e.allDay, 1.0 / 60.0);
      e.date = span.date;
      e.endDate = (span.endDate == span.date) ? QDate() : span.endDate;
      e.start = span.start;
      e.end = span.end;

      if(!rrule.isEmpty()) {
        if(parseRRule(rrule).isValid()) {
          e.rrule = rrule;
        } else {
          out.warnings << QStringLiteral("Unsupported recurrence rule on \"%1\": imported as a single event (%2)")
                              .arg(e.title.isEmpty() ? e.id : e.title, rrule);
        }
      }
      e.exdates = exdates;
      if(recurrenceId.valid) {
        // An override names the occurrence it replaces; the master is the
        // event sharing its UID.
        e.originalDate = recurrenceId.date;
        e.masterId = e.id;
        e.id = e.id + QStringLiteral("-") + detail::icsDate(recurrenceId.date);
      }
      out.events.append(e);
      continue;
    }

    if(!inEvent || nesting > 0) {
      continue;
    }

    if(cl.name == QLatin1String("UID")) {
      uid = cl.value.trimmed();
    } else if(cl.name == QLatin1String("SUMMARY")) {
      summary = detail::unescapeText(cl.value);
    } else if(cl.name == QLatin1String("LOCATION")) {
      location = detail::unescapeText(cl.value);
    } else if(cl.name == QLatin1String("DESCRIPTION")) {
      sawDescription = true;
    } else if(cl.name == QLatin1String("DTSTART")) {
      dtStart = detail::parseInstant(cl);
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
          exdates.append(at.date);
        }
      }
    }
  }

  // An unterminated VEVENT is a truncated file, not an event.
  if(inEvent) {
    out.skipped++;
  }
  return out;
}

inline QString toIcs(const QVector<CalEvent>& events) {
  QStringList lines;
  lines << QStringLiteral("BEGIN:VCALENDAR") << QStringLiteral("VERSION:2.0") << QStringLiteral("PRODID:-//heap//EN")
        << QStringLiteral("CALSCALE:GREGORIAN");

  for(const CalEvent& e : events) {
    if(!e.date.isValid()) {
      continue;
    }
    lines << QStringLiteral("BEGIN:VEVENT");
    lines << QStringLiteral("UID:") + (e.masterId.isEmpty() ? e.id : e.masterId);
    if(!e.title.isEmpty()) {
      lines << QStringLiteral("SUMMARY:") + detail::escapeText(e.title);
    }
    if(!e.context.isEmpty()) {
      lines << QStringLiteral("LOCATION:") + detail::escapeText(e.context);
    }

    const QDate last = (e.endDate.isValid() && e.endDate > e.date) ? e.endDate : e.date;
    if(e.allDay) {
      lines << QStringLiteral("DTSTART;VALUE=DATE:") + detail::icsDate(e.date);
      // Exclusive, per the spec: the day after the last one covered.
      lines << QStringLiteral("DTEND;VALUE=DATE:") + detail::icsDate(last.addDays(1));
    } else {
      lines << QStringLiteral("DTSTART:") + detail::icsDateTime(e.date, e.start);
      lines << QStringLiteral("DTEND:") + detail::icsDateTime(last, e.end);
    }
    if(!e.rrule.isEmpty()) {
      lines << QStringLiteral("RRULE:") + e.rrule;
    }
    if(!e.exdates.isEmpty()) {
      QStringList ex;
      for(const QDate& d : e.exdates) {
        if(d.isValid()) {
          ex << (e.allDay ? detail::icsDate(d) : detail::icsDateTime(d, e.start));
        }
      }
      if(!ex.isEmpty()) {
        lines << (e.allDay ? QStringLiteral("EXDATE;VALUE=DATE:") : QStringLiteral("EXDATE:")) + ex.join(QLatin1Char(','));
      }
    }
    if(e.originalDate.isValid()) {
      lines << (e.allDay ? QStringLiteral("RECURRENCE-ID;VALUE=DATE:") + detail::icsDate(e.originalDate)
                         : QStringLiteral("RECURRENCE-ID:") + detail::icsDateTime(e.originalDate, e.start));
    }
    lines << QStringLiteral("END:VEVENT");
  }
  lines << QStringLiteral("END:VCALENDAR");

  QStringList folded;
  folded.reserve(lines.size());
  for(const QString& l : lines) {
    folded << detail::foldLine(l);
  }
  return folded.join(QStringLiteral("\r\n")) + QStringLiteral("\r\n");
}

}  // namespace heap::cal
