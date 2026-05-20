#include "ChronoLocale.h"

namespace heap::chrono {

namespace {

ChronoLocale buildEnglish() {
    ChronoLocale loc;

    // ── Weekdays (full + 3-letter + 2-letter where unambiguous) ──
    const struct { const char *name; int iso; } weekdays[] = {
        {"monday",1}, {"mon",1}, {"mo",1},
        {"tuesday",2}, {"tue",2}, {"tues",2}, {"tu",2},
        {"wednesday",3}, {"wed",3}, {"we",3},
        {"thursday",4}, {"thu",4}, {"thur",4}, {"thurs",4}, {"th",4},
        {"friday",5}, {"fri",5}, {"fr",5},
        {"saturday",6}, {"sat",6}, {"sa",6},
        {"sunday",7}, {"sun",7}, {"su",7},
    };
    for (const auto &w : weekdays) loc.weekdayNames.insert(QString::fromLatin1(w.name), w.iso);

    // ── Months ──
    const struct { const char *name; int m; } months[] = {
        {"january",1}, {"jan",1},
        {"february",2}, {"feb",2},
        {"march",3}, {"mar",3},
        {"april",4}, {"apr",4},
        {"may",5},
        {"june",6}, {"jun",6},
        {"july",7}, {"jul",7},
        {"august",8}, {"aug",8},
        {"september",9}, {"sep",9}, {"sept",9},
        {"october",10}, {"oct",10},
        {"november",11}, {"nov",11},
        {"december",12}, {"dec",12},
    };
    for (const auto &mo : months) loc.monthNames.insert(QString::fromLatin1(mo.name), mo.m);

    // ── Relative adjectives (day offsets) ──
    loc.relativeAdjectives.insert(QStringLiteral("today"), 0);
    loc.relativeAdjectives.insert(QStringLiteral("tdy"), 0);
    loc.relativeAdjectives.insert(QStringLiteral("now"), 0);
    loc.relativeAdjectives.insert(QStringLiteral("tomorrow"), 1);
    loc.relativeAdjectives.insert(QStringLiteral("tmr"), 1);
    loc.relativeAdjectives.insert(QStringLiteral("tmrw"), 1);
    loc.relativeAdjectives.insert(QStringLiteral("yesterday"), -1);
    loc.relativeAdjectives.insert(QStringLiteral("yday"), -1);

    // ── Unit names → days ──
    const struct { const char *name; int days; } units[] = {
        {"day",1}, {"days",1}, {"d",1},
        {"week",7}, {"weeks",7}, {"wk",7}, {"wks",7},
        {"month",30}, {"months",30}, {"mo",30}, {"mos",30},
        {"year",365}, {"years",365}, {"yr",365}, {"yrs",365},
    };
    for (const auto &u : units) loc.unitToDays.insert(QString::fromLatin1(u.name), u.days);

    loc.weekUnits.insert(QStringLiteral("week"), 1);
    loc.weekUnits.insert(QStringLiteral("weeks"), 1);
    loc.weekUnits.insert(QStringLiteral("wk"), 1);
    loc.weekUnits.insert(QStringLiteral("wks"), 1);

    loc.monthUnits.insert(QStringLiteral("month"), 1);
    loc.monthUnits.insert(QStringLiteral("months"), 1);
    loc.monthUnits.insert(QStringLiteral("mos"), 1);

    loc.yearUnits.insert(QStringLiteral("year"), 1);
    loc.yearUnits.insert(QStringLiteral("years"), 1);
    loc.yearUnits.insert(QStringLiteral("yr"), 1);
    loc.yearUnits.insert(QStringLiteral("yrs"), 1);

    // ── Prefixes / connectors ──
    loc.relPrefixes  << QStringLiteral("in");
    loc.nextAdjectives << QStringLiteral("next");
    loc.thisAdjectives << QStringLiteral("this");
    loc.everyAdjectives << QStringLiteral("every") << QStringLiteral("each");
    loc.atWords << QStringLiteral("at") << QStringLiteral("@");
    loc.toWords << QStringLiteral("to") << QStringLiteral("until") << QStringLiteral("till");
    loc.fromWords << QStringLiteral("from");
    loc.hourSuffixes << QStringLiteral("h");
    loc.suffixes << QStringLiteral("ago");

    loc.prefixes << QStringLiteral("in")
                 << QStringLiteral("next")
                 << QStringLiteral("this")
                 << QStringLiteral("every")
                 << QStringLiteral("each")
                 << QStringLiteral("on")
                 << QStringLiteral("at");

    loc.amSuffix = QStringLiteral("am");
    loc.pmSuffix = QStringLiteral("pm");

    loc.timeRe = QRegularExpression(QStringLiteral("^(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?$"),
                                    QRegularExpression::CaseInsensitiveOption);
    loc.numericDateRe = QRegularExpression(QStringLiteral(
        "^(\\d{4})-(\\d{1,2})-(\\d{1,2})$"
        "|^(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?$"
        "|^(\\d{1,2})\\.(\\d{1,2})(?:\\.(\\d{2,4}))?$"));

    return loc;
}

} // namespace

const ChronoLocale &englishLocale() {
    static const ChronoLocale loc = buildEnglish();
    return loc;
}

} // namespace heap::chrono
