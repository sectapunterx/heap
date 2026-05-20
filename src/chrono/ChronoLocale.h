#pragma once

#include <QHash>
#include <QRegularExpression>
#include <QString>
#include <QStringList>

namespace heap::chrono {

/// Bag of word lists for a single language. Lookups are case-insensitive
/// because every key is stored lower-cased.
struct ChronoLocale {
    // Weekday name -> ISO day number (Monday = 1 … Sunday = 7).
    QHash<QString, int> weekdayNames;

    // Month name -> 1..12 (handle inflections: "мая" and "май" both -> 5).
    QHash<QString, int> monthNames;

    // Relative adjectives: "today" -> 0, "tomorrow" -> +1, "yesterday" -> -1,
    // "послезавтра" -> +2, "позавчера" -> -2.
    QHash<QString, int> relativeAdjectives;

    // Unit names mapped to *days*. "week" -> 7, "месяц" -> 30 (approx),
    // "year" -> 365. The parser also knows the canonical bucket so it can
    // call QDate::addMonths / addYears for exact arithmetic.
    QHash<QString, int> unitToDays;

    // "month"-class units that should use addMonths instead of addDays.
    QHash<QString, int> monthUnits;
    // "year"-class units that should use addYears.
    QHash<QString, int> yearUnits;
    // "week"-class units (still days*7 but we surface them for clarity).
    QHash<QString, int> weekUnits;

    QStringList prefixes;  // "in", "через", "next", "след", "every", "каждую", "каждый", "this"
    QStringList suffixes;  // "ago", "назад"

    // Words that mean "this/current" — for "this monday".
    QStringList thisAdjectives;
    // Words that mean "next" — for "next monday" / "след понедельник".
    QStringList nextAdjectives;
    // Words that introduce a relative offset: "in 2 days", "через 3 дня".
    QStringList relPrefixes;
    // Words that mark recurrence: "every", "каждую", "каждый".
    QStringList everyAdjectives;
    // Connector words for time-of-day: "at", "в", "во".
    QStringList atWords;
    // Connector words for ranges: "до", "to", "until".
    QStringList toWords;
    // Range start markers: "from", "с".
    QStringList fromWords;
    // "hour" suffix glyphs glued to a number, like "14ч" or "14h".
    QStringList hourSuffixes;

    QString amSuffix; // "am"
    QString pmSuffix; // "pm"

    QRegularExpression timeRe;        // HH:MM
    QRegularExpression numericDateRe; // YYYY-MM-DD / DD.MM[.YYYY] / D/M/[Y]
};

const ChronoLocale &englishLocale();
const ChronoLocale &russianLocale();

} // namespace heap::chrono
