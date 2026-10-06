#pragma once

#include <QDate>
#include <QDateTime>
#include <QLocale>
#include <QString>
#include <QTime>

namespace heap::text {

// Dates and times as the UI shows them, in the UI language. Every displayed
// date goes through one of the named styles below, so English reads
// "Oct 6" and Russian "6 окт." instead of 21 hand-picked patterns
// ("dd.MM HH:mm", "d MMM", "yyyy-MM-dd"…) that ignored the language.
// QML reaches the same table through AppController.datePattern(), so both
// sides agree. Machine formats (ISO in files and state, sort keys) are not
// display text and stay where they are.
//
// Style            en                    ru
// dayMonth         Oct 6                 6 окт.
// dayMonthYear     Oct 6, 2026           6 окт. 2026
// weekdayDay       Tue, Oct 6            вт, 6 окт.
// weekdayDayYear   Tue, Oct 6, 2026      вт, 6 окт. 2026
// longDay          October 6             6 октября
// longDayYear      October 6, 2026       6 октября 2026
// longWeekday      Tuesday, October 6    вторник, 6 октября
// longWeekdayYear  Tuesday, October 6, 2026
inline QString datePattern(const QString& style, const QString& lang) {
  const bool ru = lang == QLatin1String("ru");
  if(style == QLatin1String("dayMonthYear")) {
    return ru ? QStringLiteral("d MMM yyyy") : QStringLiteral("MMM d, yyyy");
  }
  if(style == QLatin1String("weekdayDay")) {
    return ru ? QStringLiteral("ddd, d MMM") : QStringLiteral("ddd, MMM d");
  }
  if(style == QLatin1String("weekdayDayYear")) {
    return ru ? QStringLiteral("ddd, d MMM yyyy") : QStringLiteral("ddd, MMM d, yyyy");
  }
  if(style == QLatin1String("longDay")) {
    return ru ? QStringLiteral("d MMMM") : QStringLiteral("MMMM d");
  }
  if(style == QLatin1String("longDayYear")) {
    return ru ? QStringLiteral("d MMMM yyyy") : QStringLiteral("MMMM d, yyyy");
  }
  if(style == QLatin1String("longWeekday")) {
    return ru ? QStringLiteral("dddd, d MMMM") : QStringLiteral("dddd, MMMM d");
  }
  if(style == QLatin1String("longWeekdayYear")) {
    return ru ? QStringLiteral("dddd, d MMMM yyyy") : QStringLiteral("dddd, MMMM d, yyyy");
  }
  // "dayMonth", and anything unknown: the shortest readable date.
  return ru ? QStringLiteral("d MMM") : QStringLiteral("MMM d");
}

// A fixed locale per UI language, not the system one: a Russian UI on an
// English Windows still says "окт.".
inline QLocale uiLocale(const QString& lang) {
  return lang == QLatin1String("ru") ? QLocale(QLocale::Russian, QLocale::Russia) : QLocale(QLocale::English, QLocale::UnitedStates);
}

inline QString formatDate(const QDate& d, const QString& style, const QString& lang) {
  return d.isValid() ? uiLocale(lang).toString(d, datePattern(style, lang)) : QString();
}

// A clock time. The 12h / 24h setting decides, not the language: "15:15" or
// "3:15pm". `hour` is fractional (14.5 = 14:30); 24:00, the end of a day, is
// 12:00am in 12h. Theme.fmtHour is the QML twin.
inline QString formatHour(double hour, bool twelveHour) {
  const int hh = static_cast<int>(hour);
  const int mm = static_cast<int>((hour - hh) * 60 + 0.5);
  const QString mmS = QStringLiteral("%1").arg(mm, 2, 10, QLatin1Char('0'));
  if(twelveHour) {
    const int h24 = hh % 24;
    const int h12 = ((h24 + 11) % 12) + 1;
    return QStringLiteral("%1:%2%3").arg(h12).arg(mmS).arg(h24 < 12 ? QStringLiteral("am") : QStringLiteral("pm"));
  }
  return QStringLiteral("%1:%2").arg(hh, 2, 10, QLatin1Char('0')).arg(mmS);
}

inline QString formatTime(const QTime& t, bool twelveHour) {
  return t.isValid() ? formatHour(t.hour() + t.minute() / 60.0, twelveHour) : QString();
}

// "Oct 6, 15:15" / "6 окт., 15:15".
inline QString formatDateTime(const QDateTime& dt, const QString& style, const QString& lang, bool twelveHour) {
  if(!dt.isValid()) {
    return {};
  }
  return formatDate(dt.date(), style, lang) + QStringLiteral(", ") + formatTime(dt.time(), twelveHour);
}

}  // namespace heap::text
