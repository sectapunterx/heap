#include "capture/CaptureParse.h"
#include "chrono/ChronoParser.h"

#include <QRegularExpression>

#include <algorithm>
#include <cmath>

namespace heap::capture {

const QStringList& deadlineWords() {
  // "до пятницы", "к понедельнику", "ко вторнику", "due fri", "by monday".
  static const QStringList kWords = {
      QStringLiteral("до"), QStringLiteral("к"), QStringLiteral("ко"), QStringLiteral("due"), QStringLiteral("by")};
  return kWords;
}

int estimateMinutes(QStringView token) {
  static const QRegularExpression kRe(
      QStringLiteral(R"(^~(?:(\d+(?:[.,]\d+)?)\s*(h|ч|час|часа|часов)\s*(?:(\d+)\s*(m|м|мин))?|(\d+)\s*(m|м|мин|min))$)"),
      QRegularExpression::CaseInsensitiveOption);
  const auto m = kRe.matchView(token);
  if(!m.hasMatch()) {
    return 0;
  }
  if(m.hasCaptured(1)) {
    QString hours = m.captured(1);
    hours.replace(QLatin1Char(','), QLatin1Char('.'));
    const double h = hours.toDouble();
    const int extra = m.hasCaptured(3) ? m.captured(3).toInt() : 0;
    return static_cast<int>(std::lround(h * 60.0)) + extra;
  }
  return m.captured(5).toInt();
}

namespace {

// "в 9" / "at 9": a bare hour under 12 with no date and no am/pm. The parser
// takes the next 9:00, which after 9:00 is tomorrow morning; the nearer of
// 9:00 and 21:00 is what "at 9" usually means (APP-266).
QDateTime nearerBareHour(const heap::chrono::ParseResult& r, const QDateTime& now) {
  static const QRegularExpression kBare(QStringLiteral(R"(^\s*(?:в|at|к)?\s*(\d{1,2})\s*$)"), QRegularExpression::CaseInsensitiveOption);
  const auto m = kBare.match(r.consumed);
  if(!m.hasMatch() || !r.hasTime) {
    return r.start;
  }
  const int hour = m.captured(1).toInt();
  if(hour < 1 || hour > 11 || r.start.time().hour() != hour) {
    return r.start;
  }
  const QDateTime evening(now.date(), QTime(hour + 12, r.start.time().minute()));
  return evening > now && evening < r.start ? evening : r.start;
}

// "пт" said on a Friday is next Friday, not today (APP-266): a weekday is
// named to point away from today. "today"/"сегодня" and a bare time stay.
QDateTime weekdayNotToday(const heap::chrono::ParseResult& r, const QDateTime& now) {
  if(r.start.date() != now.date() || !r.recurrence.isEmpty()) {
    return r.start;
  }
  static const QRegularExpression kWeekday(
      QStringLiteral(R"((?<!\p{L})(пн|вт|ср|чт|пт|сб|вс|понед\p{L}*|вторн\p{L}*|сред\p{L}*|четв\p{L}*|пятн\p{L}*|субб\p{L}*|воскр\p{L}*|)"
                     R"(mon\p{L}*|tue\p{L}*|wed\p{L}*|thu\p{L}*|fri\p{L}*|sat\p{L}*|sun\p{L}*)(?!\p{L}))"),
      QRegularExpression::CaseInsensitiveOption | QRegularExpression::UseUnicodePropertiesOption);
  return kWeekday.match(r.consumed).hasMatch() ? r.start.addDays(7) : r.start;
}

bool isPast(const QDateTime& d, bool hasTime, const QDateTime& now) {
  return hasTime ? d < now : d.date() < now.date();
}

// The deadline word right before `at`, if one is there: its start offset,
// or -1.
int deadlineWordBefore(const QString& text, int at) {
  int end = at;
  while(end > 0 && text.at(end - 1).isSpace()) {
    --end;
  }
  int start = end;
  while(start > 0 && text.at(start - 1).isLetter()) {
    --start;
  }
  if(start == end || (start > 0 && !text.at(start - 1).isSpace() && !text.at(start - 1).isPunct())) {
    return -1;
  }
  const QString word = text.mid(start, end - start).toLower();
  return deadlineWords().contains(word) ? start : -1;
}

}  // namespace

Parsed parse(const QString& text, const heap::chrono::ChronoParser& chrono, const QDateTime& now, const QStringList& rejected) {
  Parsed out;

  // ── the estimate: "~30m" as one token ──
  static const QRegularExpression kEstimate(QStringLiteral(R"((?<=^|\s)~\S+(?:\s*\d+\s*(?:m|м|мин))?(?=\s|$))"),
                                            QRegularExpression::CaseInsensitiveOption);
  for(auto it = kEstimate.globalMatch(text); it.hasNext();) {
    const auto m = it.next();
    const int minutes = estimateMinutes(m.capturedView());
    if(minutes <= 0 || rejected.contains(m.captured())) {
      continue;
    }
    out.estimateMinutes = minutes;
    out.spans.append(
        Span{static_cast<int>(m.capturedStart()), static_cast<int>(m.capturedEnd()), QStringLiteral("estimate"), m.captured()});
    break;
  }

  // ── dates ──
  // Read with the estimate blanked out, so "~2ч" is not read as a time.
  QString scan = text;
  for(const Span& s : out.spans) {
    for(int i = s.start; i < s.end; ++i) {
      scan[i] = QLatin1Char(' ');
    }
  }
  for(const heap::chrono::ParseResult& r : chrono.parseAll(scan, now)) {
    if(!r.ok || !r.start.isValid() || r.startOffset < 0 || r.endOffset <= r.startOffset) {
      continue;
    }
    // The deadline word before the date, or the parser's own first word
    // ("до пятницы" is one phrase to it).
    int marker = deadlineWordBefore(scan, r.startOffset);
    if(marker < 0) {
      for(const QString& w : deadlineWords()) {
        const int after = r.startOffset + static_cast<int>(w.size());
        if(after < r.endOffset && scan.mid(r.startOffset, w.size()).compare(w, Qt::CaseInsensitive) == 0 && scan.at(after).isSpace()) {
          marker = r.startOffset;
          break;
        }
      }
    }
    const bool isDue = marker >= 0;
    const int from = isDue ? marker : r.startOffset;
    const QString words = text.mid(from, r.endOffset - from);
    if(rejected.contains(words)) {
      continue;
    }
    if(isDue) {
      if(out.due.isValid()) {
        continue;
      }
      out.due = weekdayNotToday(r, now);
      out.dueHasTime = r.hasTime;
      out.duePast = isPast(out.due, r.hasTime, now);
    } else {
      if(out.when.isValid()) {
        continue;
      }
      out.when = weekdayNotToday(r, now);
      if(out.when == r.start) {
        out.when = nearerBareHour(r, now);
      }
      out.whenHasTime = r.hasTime;
      out.whenPast = isPast(out.when, r.hasTime, now);
      if(r.end.isValid() && r.end > r.start) {
        out.whenEnd = r.end;
      }
    }
    if(!r.recurrence.isEmpty() && out.recurrence.isEmpty()) {
      out.recurrence = r.recurrence;
    }
    out.spans.append(Span{from, r.endOffset, isDue ? QStringLiteral("due") : QStringLiteral("when"), words});
  }

  std::sort(out.spans.begin(), out.spans.end(), [](const Span& a, const Span& b) {
    return a.start < b.start;
  });
  QString title;
  int at = 0;
  for(const Span& s : out.spans) {
    title += text.mid(at, s.start - at);
    title += QLatin1Char(' ');
    at = s.end;
  }
  title += text.mid(at);
  out.title = title.simplified();
  // A cut leaves its comma behind: "do it , then" reads "do it, then".
  out.title.replace(QStringLiteral(" ,"), QStringLiteral(","));
  while(out.title.startsWith(QLatin1Char(',')) || out.title.startsWith(QLatin1Char('-'))) {
    out.title = out.title.mid(1).trimmed();
  }
  // A comma or dash left dangling where a date was cut out ("call Ann, ").
  while(!out.title.isEmpty() && (out.title.endsWith(QLatin1Char(',')) || out.title.endsWith(QLatin1Char('-')))) {
    out.title.chop(1);
    out.title = out.title.trimmed();
  }
  return out;
}

}  // namespace heap::capture
