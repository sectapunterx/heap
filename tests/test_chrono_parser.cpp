#include <gtest/gtest.h>

#include "chrono/ChronoParser.h"

#include <QDate>
#include <QDateTime>
#include <QLocale>
#include <QString>
#include <QTime>

using heap::chrono::ChronoParser;
using heap::chrono::ParseResult;

namespace {

const QDate kRefDate(2026, 5, 20);   // Wednesday
const QTime kRefTime(10, 0);
const QDateTime kRef(kRefDate, kRefTime);

class Chrono : public ::testing::Test {
protected:
    ChronoParser parserEn{QLocale(QLocale::English, QLocale::UnitedStates)};
    ChronoParser parserRu{QLocale(QLocale::Russian, QLocale::Russia)};
};

#define EXPECT_OK(r) ASSERT_TRUE((r).ok) << "parse failed for input"
#define EXPECT_DATE(r, y, m, d) EXPECT_EQ((r).start.date(), QDate(y, m, d))
#define EXPECT_TIME(r, h, mi)   EXPECT_EQ((r).start.time(), QTime(h, mi))

} // namespace

// ── English absolutes ────────────────────────────────────────────────────
TEST_F(Chrono, IsoDate) {
    auto r = parserEn.parse("2026-05-22", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
    EXPECT_FALSE(r.hasTime);
}
TEST_F(Chrono, IsoDatePastYear) {
    auto r = parserEn.parse("2024-01-09", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2024, 1, 9);
}
TEST_F(Chrono, EnMonthDay) {
    auto r = parserEn.parse("May 22", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, EnDayMonth) {
    auto r = parserEn.parse("22 May", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, EnMonthDayYear) {
    auto r = parserEn.parse("May 22 2026", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, EnFullMonth) {
    auto r = parserEn.parse("december 31", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 12, 31);
}
TEST_F(Chrono, EnShortMonth) {
    auto r = parserEn.parse("Jan 1", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 1, 1);
}
TEST_F(Chrono, EnSlashDateMonthFirst) {
    auto r = parserEn.parse("5/22/2026", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, EnSlashDateAmbiguousUsesLocale) {
    auto r = parserEn.parse("5/6/2026", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 6);
}
TEST_F(Chrono, EnSlashDateShortYear) {
    auto r = parserEn.parse("5/22/26", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}

// ── Russian absolutes ────────────────────────────────────────────────────
TEST_F(Chrono, RuDottedDate) {
    auto r = parserRu.parse("22.05", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, RuDottedDateYear) {
    auto r = parserRu.parse("22.05.2026", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, RuDottedShortYear) {
    auto r = parserRu.parse("22.05.26", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, RuMonthGenitive) {
    auto r = parserRu.parse(QString::fromUtf8("22 мая"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, RuMonthGenitiveYear) {
    auto r = parserRu.parse(QString::fromUtf8("22 мая 2027"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2027, 5, 22);
}
TEST_F(Chrono, RuMonthAbbrev) {
    auto r = parserRu.parse(QString::fromUtf8("3 сен"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 9, 3);
}
TEST_F(Chrono, RuSlashLocale) {
    auto r = parserRu.parse("5/6/2026", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 6, 5);
}
TEST_F(Chrono, RuFullMonthName) {
    auto r = parserRu.parse(QString::fromUtf8("1 декабря"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 12, 1);
}

// ── Relative adjectives ─────────────────────────────────────────────────
TEST_F(Chrono, EnToday) {
    auto r = parserEn.parse("today", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 20);
}
TEST_F(Chrono, EnTomorrow) {
    auto r = parserEn.parse("tomorrow", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21);
}
TEST_F(Chrono, EnYesterday) {
    auto r = parserEn.parse("yesterday", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 19);
}
TEST_F(Chrono, EnAbbreviations) {
    auto r = parserEn.parse("tmr", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21);
}
TEST_F(Chrono, RuToday) {
    auto r = parserRu.parse(QString::fromUtf8("сегодня"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 20);
}
TEST_F(Chrono, RuTomorrow) {
    auto r = parserRu.parse(QString::fromUtf8("завтра"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21);
}
TEST_F(Chrono, RuDayAfterTomorrow) {
    auto r = parserRu.parse(QString::fromUtf8("послезавтра"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, RuYesterday) {
    auto r = parserRu.parse(QString::fromUtf8("вчера"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 19);
}

// ── in/через N units ────────────────────────────────────────────────────
TEST_F(Chrono, InDays) {
    auto r = parserEn.parse("in 3 days", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 23);
}
TEST_F(Chrono, InOneDay) {
    auto r = parserEn.parse("in 1 day", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21);
}
TEST_F(Chrono, InWeeks) {
    auto r = parserEn.parse("in 2 weeks", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 6, 3);
}
TEST_F(Chrono, InMonth) {
    auto r = parserEn.parse("in 1 month", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 6, 20);
}
TEST_F(Chrono, InMonths) {
    auto r = parserEn.parse("in 3 months", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 8, 20);
}
TEST_F(Chrono, InYear) {
    auto r = parserEn.parse("in 1 year", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2027, 5, 20);
}
TEST_F(Chrono, RuCherezDays) {
    auto r = parserRu.parse(QString::fromUtf8("через 3 дня"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 23);
}
TEST_F(Chrono, RuCherezDayShort) {
    auto r = parserRu.parse(QString::fromUtf8("через 1 день"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21);
}
TEST_F(Chrono, RuCherezWeeks) {
    auto r = parserRu.parse(QString::fromUtf8("через 2 недели"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 6, 3);
}
TEST_F(Chrono, RuCherezMonth) {
    auto r = parserRu.parse(QString::fromUtf8("через 1 месяц"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 6, 20);
}
TEST_F(Chrono, RuCherezYear) {
    auto r = parserRu.parse(QString::fromUtf8("через 1 год"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2027, 5, 20);
}
TEST_F(Chrono, AgoDays) {
    auto r = parserEn.parse("3 days ago", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 17);
}
TEST_F(Chrono, AgoMonth) {
    auto r = parserEn.parse("1 month ago", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 4, 20);
}
TEST_F(Chrono, RuNazadDays) {
    auto r = parserRu.parse(QString::fromUtf8("3 дня назад"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 17);
}

// ── Weekdays bare ───────────────────────────────────────────────────────
TEST_F(Chrono, MondayBare) {
    auto r = parserEn.parse("monday", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25);
}
TEST_F(Chrono, FridayBare) {
    auto r = parserEn.parse("friday", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, WednesdayBareToday) {
    auto r = parserEn.parse("wednesday", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 20);
}
TEST_F(Chrono, MonAbbrev) {
    auto r = parserEn.parse("mon", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25);
}
TEST_F(Chrono, RuPnAbbrev) {
    auto r = parserRu.parse(QString::fromUtf8("пн"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25);
}
TEST_F(Chrono, RuPonedelnik) {
    auto r = parserRu.parse(QString::fromUtf8("понедельник"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25);
}

// ── Next weekday ────────────────────────────────────────────────────────
TEST_F(Chrono, NextMonday) {
    auto r = parserEn.parse("next monday", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25);
}
TEST_F(Chrono, NextMondayShort) {
    auto r = parserEn.parse("next mon", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25);
}
TEST_F(Chrono, NextWednesdayJumpsAWeek) {
    auto r = parserEn.parse("next wed", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 27);
}
TEST_F(Chrono, RuSlPn) {
    auto r = parserRu.parse(QString::fromUtf8("след пн"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25);
}
TEST_F(Chrono, RuSlDotPn) {
    auto r = parserRu.parse(QString::fromUtf8("след. понедельник"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25);
}
TEST_F(Chrono, RuSleduyushhayaSreda) {
    auto r = parserRu.parse(QString::fromUtf8("следующая среда"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 27);
}

// ── Time of day ─────────────────────────────────────────────────────────
TEST_F(Chrono, Time1400) {
    auto r = parserEn.parse("14:00", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 20);
    EXPECT_TRUE(r.hasTime); EXPECT_TIME(r, 14, 0);
}
TEST_F(Chrono, Time2pm) {
    auto r = parserEn.parse("2pm", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 14, 0); EXPECT_TRUE(r.hasTime);
}
TEST_F(Chrono, Time12am) {
    auto r = parserEn.parse("12am", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 0, 0);
}
TEST_F(Chrono, Time12pm) {
    auto r = parserEn.parse("12pm", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 12, 0);
}
TEST_F(Chrono, TimeAt2pm) {
    auto r = parserEn.parse("at 2pm", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 14, 0);
}
TEST_F(Chrono, RuVDva) {
    auto r = parserRu.parse(QString::fromUtf8("в 2"), kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 2, 0); EXPECT_TRUE(r.hasTime);
}
TEST_F(Chrono, Ru14ch) {
    auto r = parserRu.parse(QString::fromUtf8("14ч"), kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 14, 0); EXPECT_TRUE(r.hasTime);
}
TEST_F(Chrono, TimeHM) {
    auto r = parserEn.parse("9:30", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 9, 30);
}

// ── Date + time combos ──────────────────────────────────────────────────
TEST_F(Chrono, RuTomorrowAt14) {
    auto r = parserRu.parse(QString::fromUtf8("завтра в 14:00"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21); EXPECT_TIME(r, 14, 0);
    EXPECT_TRUE(r.hasTime);
}
TEST_F(Chrono, RuTomorrowAt2pm) {
    auto r = parserRu.parse(QString::fromUtf8("завтра в 2pm"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21); EXPECT_TIME(r, 14, 0);
}
TEST_F(Chrono, EnTomorrow2pm) {
    auto r = parserEn.parse("tomorrow 2pm", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21); EXPECT_TIME(r, 14, 0);
}
TEST_F(Chrono, EnFridayAt9) {
    auto r = parserEn.parse("Friday at 9", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22); EXPECT_TIME(r, 9, 0);
    EXPECT_TRUE(r.hasTime);
}
TEST_F(Chrono, EnMondayAt9_30) {
    auto r = parserEn.parse("monday at 9:30", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25); EXPECT_TIME(r, 9, 30);
}
TEST_F(Chrono, RuPonedelnikV10) {
    auto r = parserRu.parse(QString::fromUtf8("понедельник в 10"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25); EXPECT_TIME(r, 10, 0);
}
TEST_F(Chrono, RuCherezDaysAt15) {
    auto r = parserRu.parse(QString::fromUtf8("через 3 дня в 15:00"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 23); EXPECT_TIME(r, 15, 0);
}
TEST_F(Chrono, IsoDateAt2pm) {
    auto r = parserEn.parse("2026-05-22 14:00", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22); EXPECT_TIME(r, 14, 0);
}
TEST_F(Chrono, EnMayDayTime) {
    auto r = parserEn.parse("May 22 at 9:00", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22); EXPECT_TIME(r, 9, 0);
}
TEST_F(Chrono, RuMayDayTime) {
    auto r = parserRu.parse(QString::fromUtf8("22 мая в 9:00"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22); EXPECT_TIME(r, 9, 0);
}

// ── Ranges ──────────────────────────────────────────────────────────────
TEST_F(Chrono, RangeBareHours) {
    auto r = parserEn.parse("9-10", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 9, 0);
    EXPECT_EQ(r.end.time(), QTime(10, 0));
}
TEST_F(Chrono, RangePm) {
    auto r = parserEn.parse("2-3pm", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 14, 0);
    EXPECT_EQ(r.end.time(), QTime(15, 0));
}
TEST_F(Chrono, RangeFromTo) {
    auto r = parserEn.parse("from 14:00 to 15:00", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 14, 0);
    EXPECT_EQ(r.end.time(), QTime(15, 0));
}
TEST_F(Chrono, RuRangeS_Do) {
    auto r = parserRu.parse(QString::fromUtf8("с 14 до 15"), kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 14, 0);
    EXPECT_EQ(r.end.time(), QTime(15, 0));
}
TEST_F(Chrono, RangeWithDate) {
    auto r = parserEn.parse("tomorrow 9-10", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21);
    EXPECT_TIME(r, 9, 0);
    EXPECT_EQ(r.end.time(), QTime(10, 0));
}
TEST_F(Chrono, RuRangeWithDate) {
    auto r = parserRu.parse(QString::fromUtf8("завтра в 14:00-15:00"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21);
    EXPECT_TIME(r, 14, 0);
    EXPECT_EQ(r.end.time(), QTime(15, 0));
}

// ── Recurrence ──────────────────────────────────────────────────────────
TEST_F(Chrono, EveryMonday) {
    auto r = parserEn.parse("every monday", kRef);
    EXPECT_OK(r);
    EXPECT_EQ(r.recurrence, QStringLiteral("every:mon"));
    EXPECT_DATE(r, 2026, 5, 25);
}
TEST_F(Chrono, EveryWednesdayToday) {
    auto r = parserEn.parse("every wednesday", kRef);
    EXPECT_OK(r);
    EXPECT_EQ(r.recurrence, QStringLiteral("every:wed"));
    EXPECT_DATE(r, 2026, 5, 20);
}
TEST_F(Chrono, EveryWeekday) {
    auto r = parserEn.parse("every weekday", kRef);
    EXPECT_OK(r);
    EXPECT_EQ(r.recurrence, QStringLiteral("every:weekday"));
}
TEST_F(Chrono, RuKazhduyuSredu) {
    auto r = parserRu.parse(QString::fromUtf8("каждую среду"), kRef);
    EXPECT_OK(r);
    EXPECT_EQ(r.recurrence, QStringLiteral("every:wed"));
}
TEST_F(Chrono, RuKazhdyDen) {
    auto r = parserRu.parse(QString::fromUtf8("каждый день"), kRef);
    EXPECT_OK(r);
    EXPECT_EQ(r.recurrence, QStringLiteral("every:day"));
}

// ── Failure & ambiguity ─────────────────────────────────────────────────
TEST_F(Chrono, GibberishFails) {
    auto r = parserEn.parse("xyz", kRef);
    EXPECT_FALSE(r.ok);
}
TEST_F(Chrono, EmptyInputFails) {
    auto r = parserEn.parse("", kRef);
    EXPECT_FALSE(r.ok);
}
TEST_F(Chrono, BareNumberFails) {
    auto r = parserEn.parse("42", kRef);
    EXPECT_FALSE(r.ok);
}
TEST_F(Chrono, BareDashFails) {
    auto r = parserEn.parse("-", kRef);
    EXPECT_FALSE(r.ok);
}
TEST_F(Chrono, NoTimeMarkerFails) {
    auto r = parserEn.parse("tomorrow 14", kRef);
    // date still resolves, but should not include hasTime
    EXPECT_OK(r);
    EXPECT_DATE(r, 2026, 5, 21);
    EXPECT_FALSE(r.hasTime);
}
TEST_F(Chrono, InvalidDateFails) {
    auto r = parserEn.parse("2026-13-40", kRef);
    EXPECT_FALSE(r.ok);
}

// ── Consumed substring & offsets ────────────────────────────────────────
TEST_F(Chrono, ConsumedTrailingText) {
    auto r = parserEn.parse("call mom tomorrow at 9am", kRef);
    EXPECT_OK(r);
    EXPECT_DATE(r, 2026, 5, 21);
    EXPECT_TIME(r, 9, 0);
    EXPECT_GE(r.startOffset, 0);
    EXPECT_GT(r.endOffset, r.startOffset);
    EXPECT_EQ(r.consumed, QStringLiteral("tomorrow at 9am"));
}
TEST_F(Chrono, ConsumedLeadingText) {
    auto r = parserRu.parse(QString::fromUtf8("купить хлеб завтра"), kRef);
    EXPECT_OK(r);
    EXPECT_DATE(r, 2026, 5, 21);
    EXPECT_EQ(r.consumed, QString::fromUtf8("завтра"));
}

// ── ParseAll ────────────────────────────────────────────────────────────
TEST_F(Chrono, ParseAllPicksFirst) {
    auto v = parserEn.parseAll("today and tomorrow", kRef);
    ASSERT_GE(v.size(), 1);
    EXPECT_DATE(v[0], 2026, 5, 20);
}

// ── Boundary cases ──────────────────────────────────────────────────────
TEST_F(Chrono, IsoDateEndOfMonth) {
    auto r = parserEn.parse("2026-02-28", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 2, 28);
}
TEST_F(Chrono, IsoDateLeap) {
    auto r = parserEn.parse("2024-02-29", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2024, 2, 29);
}
TEST_F(Chrono, MonthOverflow) {
    auto r = parserEn.parse("in 14 months", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2027, 7, 20);
}
TEST_F(Chrono, NegativeAgoCrossYear) {
    auto r = parserEn.parse("6 months ago", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2025, 11, 20);
}

// ── More relative variations ────────────────────────────────────────────
TEST_F(Chrono, EnInWk) {
    auto r = parserEn.parse("in 2 wk", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 6, 3);
}
TEST_F(Chrono, EnInD) {
    auto r = parserEn.parse("in 5 d", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 25);
}
TEST_F(Chrono, RuMidWord) {
    auto r = parserRu.parse(QString::fromUtf8("через 2 нед"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 6, 3);
}

// ── Reference time defaults ─────────────────────────────────────────────
TEST_F(Chrono, DefaultsToNowIfNoRef) {
    auto r = parserEn.parse("today", QDateTime());
    EXPECT_OK(r);
    // Should fall back to current date.
    EXPECT_EQ(r.start.date(), QDate::currentDate());
}

// ── Mixed-lang regression ───────────────────────────────────────────────
TEST_F(Chrono, MixedRuEn) {
    auto r = parserRu.parse(QString::fromUtf8("завтра в 2pm"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21); EXPECT_TIME(r, 14, 0);
}

// ── Title-extraction style ──────────────────────────────────────────────
TEST_F(Chrono, TitleAndTime) {
    auto r = parserRu.parse(QString::fromUtf8("Звонок Пете завтра в 18:00"), kRef);
    EXPECT_OK(r);
    EXPECT_DATE(r, 2026, 5, 21);
    EXPECT_TIME(r, 18, 0);
}

// ── Locale-aware slash with parserRu vs parserEn for same input ─────────
TEST_F(Chrono, LocaleAffectsSlashOrder) {
    auto en = parserEn.parse("5/6/2026", kRef);
    auto ru = parserRu.parse("5/6/2026", kRef);
    EXPECT_OK(en); EXPECT_OK(ru);
    EXPECT_EQ(en.start.date(), QDate(2026, 5, 6));
    EXPECT_EQ(ru.start.date(), QDate(2026, 6, 5));
}

// ── Hour suffix variants ────────────────────────────────────────────────
TEST_F(Chrono, EnHourH) {
    auto r = parserEn.parse("16h", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 16, 0);
}
TEST_F(Chrono, RuHourFull) {
    auto r = parserRu.parse(QString::fromUtf8("16 часов"), kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 16, 0);
}

// ── Final assorted ─────────────────────────────────────────────────────
TEST_F(Chrono, EnTodaySlashTime) {
    auto r = parserEn.parse("today 9:15", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 20); EXPECT_TIME(r, 9, 15);
}
TEST_F(Chrono, RuPosleZavtra) {
    auto r = parserRu.parse(QString::fromUtf8("позавчера"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 18);
}
TEST_F(Chrono, EnNextFri) {
    auto r = parserEn.parse("next friday", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 22);
}
TEST_F(Chrono, EnNextSunday) {
    auto r = parserEn.parse("next sunday", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 24);
}
TEST_F(Chrono, RuVtornik) {
    auto r = parserRu.parse(QString::fromUtf8("вторник"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 26);
}
TEST_F(Chrono, RuChetverg) {
    auto r = parserRu.parse(QString::fromUtf8("четверг"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21);
}
TEST_F(Chrono, IsoTimeOnly) {
    auto r = parserEn.parse("08:45", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 8, 45); EXPECT_TRUE(r.hasTime);
}
TEST_F(Chrono, MidnightMarker) {
    auto r = parserEn.parse("00:00", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 0, 0); EXPECT_TRUE(r.hasTime);
}

// ── Space-separated time ────────────────────────────────────────────────
TEST_F(Chrono, SpaceTime1800) {
    auto r = parserEn.parse("18 00", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 18, 0); EXPECT_TRUE(r.hasTime);
}
TEST_F(Chrono, SpaceTimeWithMinutes) {
    auto r = parserEn.parse("9 30", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 9, 30);
}
TEST_F(Chrono, RuTomorrowSpaceTime) {
    auto r = parserRu.parse(QString::fromUtf8("завтра в 18 00"), kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21); EXPECT_TIME(r, 18, 0);
}
TEST_F(Chrono, EnTomorrowSpaceTime) {
    auto r = parserEn.parse("tomorrow 14 30", kRef);
    EXPECT_OK(r); EXPECT_DATE(r, 2026, 5, 21); EXPECT_TIME(r, 14, 30);
}
TEST_F(Chrono, SpaceTimeRange) {
    auto r = parserEn.parse("18 00 - 19 00", kRef);
    EXPECT_OK(r); EXPECT_TIME(r, 18, 0);
    EXPECT_EQ(r.end.time(), QTime(19, 0));
}
TEST_F(Chrono, SpaceMinuteRequiresTwoDigits) {
    // "in 2 weeks" must not be eaten as 2:weeks. "in" routes via relative
    // prefix, but as a regression check ensure "2 weeks" alone never
    // resolves to a time.
    auto r = parserEn.parse("2 weeks", kRef);
    EXPECT_FALSE(r.ok);
}
