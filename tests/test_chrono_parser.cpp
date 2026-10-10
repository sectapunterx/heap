#include "chrono/ChronoParser.h"

#include <QDate>
#include <QDateTime>
#include <QLocale>
#include <QString>
#include <QTime>

#include <gtest/gtest.h>

using heap::chrono::ChronoParser;
using heap::chrono::ParseResult;

namespace {

const QDate kRefDate(2026, 5, 20);  // Wednesday
const QTime kRefTime(10, 0);
const QDateTime kRef(kRefDate, kRefTime);

class Chrono : public ::testing::Test {
 protected:
  ChronoParser parserEn{QLocale(QLocale::English, QLocale::UnitedStates)};
  ChronoParser parserRu{QLocale(QLocale::Russian, QLocale::Russia)};
};

#define EXPECT_OK(r)            ASSERT_TRUE((r).ok) << "parse failed for input"
#define EXPECT_DATE(r, y, m, d) EXPECT_EQ((r).start.date(), QDate(y, m, d))
#define EXPECT_TIME(r, h, mi)   EXPECT_EQ((r).start.time(), QTime(h, mi))

}  // namespace

// ── English absolutes ────────────────────────────────────────────────────
TEST_F(Chrono, IsoDate) {
  auto r = parserEn.parse("2026-05-22", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
  EXPECT_FALSE(r.hasTime);
}

TEST_F(Chrono, IsoDatePastYear) {
  auto r = parserEn.parse("2024-01-09", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2024, 1, 9);
}

TEST_F(Chrono, EnMonthDay) {
  auto r = parserEn.parse("May 22", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, EnDayMonth) {
  auto r = parserEn.parse("22 May", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, EnMonthDayYear) {
  auto r = parserEn.parse("May 22 2026", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, EnFullMonth) {
  auto r = parserEn.parse("december 31", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 12, 31);
}

TEST_F(Chrono, EnShortMonth) {
  // Already past on kRef: the next Jan 1 (IDIOT-TASKS-6).
  auto r = parserEn.parse("Jan 1", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2027, 1, 1);
}

TEST_F(Chrono, EnSlashDateMonthFirst) {
  auto r = parserEn.parse("5/22/2026", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, EnSlashDateAmbiguousUsesLocale) {
  auto r = parserEn.parse("5/6/2026", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 6);
}

TEST_F(Chrono, EnSlashDateShortYear) {
  auto r = parserEn.parse("5/22/26", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

// ── Russian absolutes ────────────────────────────────────────────────────
TEST_F(Chrono, RuDottedDate) {
  auto r = parserRu.parse("22.05", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, RuDottedDateYear) {
  auto r = parserRu.parse("22.05.2026", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, RuDottedShortYear) {
  auto r = parserRu.parse("22.05.26", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, RuMonthGenitive) {
  auto r = parserRu.parse(QString::fromUtf8("22 мая"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, RuMonthGenitiveYear) {
  auto r = parserRu.parse(QString::fromUtf8("22 мая 2027"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2027, 5, 22);
}

TEST_F(Chrono, RuMonthAbbrev) {
  auto r = parserRu.parse(QString::fromUtf8("3 сен"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 9, 3);
}

TEST_F(Chrono, RuSlashLocale) {
  auto r = parserRu.parse("5/6/2026", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 6, 5);
}

TEST_F(Chrono, RuFullMonthName) {
  auto r = parserRu.parse(QString::fromUtf8("1 декабря"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 12, 1);
}

// ── Relative adjectives ─────────────────────────────────────────────────
TEST_F(Chrono, EnToday) {
  auto r = parserEn.parse("today", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 20);
}

TEST_F(Chrono, EnTomorrow) {
  auto r = parserEn.parse("tomorrow", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
}

TEST_F(Chrono, EnYesterday) {
  auto r = parserEn.parse("yesterday", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 19);
}

TEST_F(Chrono, EnAbbreviations) {
  auto r = parserEn.parse("tmr", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
}

TEST_F(Chrono, RuToday) {
  auto r = parserRu.parse(QString::fromUtf8("сегодня"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 20);
}

TEST_F(Chrono, RuTomorrow) {
  auto r = parserRu.parse(QString::fromUtf8("завтра"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
}

TEST_F(Chrono, RuDayAfterTomorrow) {
  auto r = parserRu.parse(QString::fromUtf8("послезавтра"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, RuYesterday) {
  auto r = parserRu.parse(QString::fromUtf8("вчера"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 19);
}

// ── in/через N units ────────────────────────────────────────────────────
TEST_F(Chrono, InDays) {
  auto r = parserEn.parse("in 3 days", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 23);
}

TEST_F(Chrono, InOneDay) {
  auto r = parserEn.parse("in 1 day", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
}

TEST_F(Chrono, InWeeks) {
  auto r = parserEn.parse("in 2 weeks", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 6, 3);
}

TEST_F(Chrono, InMonth) {
  auto r = parserEn.parse("in 1 month", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 6, 20);
}

TEST_F(Chrono, InMonths) {
  auto r = parserEn.parse("in 3 months", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 8, 20);
}

TEST_F(Chrono, InYear) {
  auto r = parserEn.parse("in 1 year", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2027, 5, 20);
}

TEST_F(Chrono, RuCherezDays) {
  auto r = parserRu.parse(QString::fromUtf8("через 3 дня"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 23);
}

TEST_F(Chrono, RuCherezDayShort) {
  auto r = parserRu.parse(QString::fromUtf8("через 1 день"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
}

TEST_F(Chrono, RuCherezWeeks) {
  auto r = parserRu.parse(QString::fromUtf8("через 2 недели"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 6, 3);
}

TEST_F(Chrono, RuCherezMonth) {
  auto r = parserRu.parse(QString::fromUtf8("через 1 месяц"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 6, 20);
}

TEST_F(Chrono, RuCherezYear) {
  auto r = parserRu.parse(QString::fromUtf8("через 1 год"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2027, 5, 20);
}

TEST_F(Chrono, AgoDays) {
  auto r = parserEn.parse("3 days ago", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 17);
}

TEST_F(Chrono, AgoMonth) {
  auto r = parserEn.parse("1 month ago", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 4, 20);
}

TEST_F(Chrono, RuNazadDays) {
  auto r = parserRu.parse(QString::fromUtf8("3 дня назад"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 17);
}

// ── Weekdays bare ───────────────────────────────────────────────────────
TEST_F(Chrono, MondayBare) {
  auto r = parserEn.parse("monday", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
}

TEST_F(Chrono, FridayBare) {
  auto r = parserEn.parse("friday", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, WednesdayBareToday) {
  auto r = parserEn.parse("wednesday", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 20);
}

TEST_F(Chrono, MonAbbrev) {
  auto r = parserEn.parse("mon", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
}

TEST_F(Chrono, RuPnAbbrev) {
  auto r = parserRu.parse(QString::fromUtf8("пн"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
}

TEST_F(Chrono, RuPonedelnik) {
  auto r = parserRu.parse(QString::fromUtf8("понедельник"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
}

// ── Next weekday ────────────────────────────────────────────────────────
TEST_F(Chrono, NextMonday) {
  auto r = parserEn.parse("next monday", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
}

TEST_F(Chrono, NextMondayShort) {
  auto r = parserEn.parse("next mon", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
}

TEST_F(Chrono, NextWednesdayJumpsAWeek) {
  auto r = parserEn.parse("next wed", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 27);
}

TEST_F(Chrono, RuSlPn) {
  auto r = parserRu.parse(QString::fromUtf8("след пн"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
}

TEST_F(Chrono, RuSlDotPn) {
  auto r = parserRu.parse(QString::fromUtf8("след. понедельник"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
}

TEST_F(Chrono, RuSleduyushhayaSreda) {
  auto r = parserRu.parse(QString::fromUtf8("следующая среда"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 27);
}

// ── Time of day ─────────────────────────────────────────────────────────
TEST_F(Chrono, Time1400) {
  auto r = parserEn.parse("14:00", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 20);
  EXPECT_TRUE(r.hasTime);
  EXPECT_TIME(r, 14, 0);
}

TEST_F(Chrono, Time2pm) {
  auto r = parserEn.parse("2pm", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 14, 0);
  EXPECT_TRUE(r.hasTime);
}

TEST_F(Chrono, Time12am) {
  auto r = parserEn.parse("12am", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 0, 0);
}

TEST_F(Chrono, Time12pm) {
  auto r = parserEn.parse("12pm", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 12, 0);
}

TEST_F(Chrono, TimeAt2pm) {
  auto r = parserEn.parse("at 2pm", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 14, 0);
}

TEST_F(Chrono, RuVDva) {
  auto r = parserRu.parse(QString::fromUtf8("в 2"), kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 2, 0);
  EXPECT_TRUE(r.hasTime);
}

TEST_F(Chrono, Ru14ch) {
  auto r = parserRu.parse(QString::fromUtf8("14ч"), kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 14, 0);
  EXPECT_TRUE(r.hasTime);
}

TEST_F(Chrono, TimeHM) {
  auto r = parserEn.parse("9:30", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 9, 30);
}

// ── Date + time combos ──────────────────────────────────────────────────
TEST_F(Chrono, RuTomorrowAt14) {
  auto r = parserRu.parse(QString::fromUtf8("завтра в 14:00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 14, 0);
  EXPECT_TRUE(r.hasTime);
}

TEST_F(Chrono, RuTomorrowAt2pm) {
  auto r = parserRu.parse(QString::fromUtf8("завтра в 2pm"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 14, 0);
}

TEST_F(Chrono, EnTomorrow2pm) {
  auto r = parserEn.parse("tomorrow 2pm", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 14, 0);
}

TEST_F(Chrono, EnFridayAt9) {
  auto r = parserEn.parse("Friday at 9", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
  EXPECT_TIME(r, 9, 0);
  EXPECT_TRUE(r.hasTime);
}

TEST_F(Chrono, EnMondayAt9_30) {
  auto r = parserEn.parse("monday at 9:30", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_TIME(r, 9, 30);
}

TEST_F(Chrono, RuPonedelnikV10) {
  auto r = parserRu.parse(QString::fromUtf8("понедельник в 10"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_TIME(r, 10, 0);
}

TEST_F(Chrono, RuCherezDaysAt15) {
  auto r = parserRu.parse(QString::fromUtf8("через 3 дня в 15:00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 23);
  EXPECT_TIME(r, 15, 0);
}

TEST_F(Chrono, IsoDateAt2pm) {
  auto r = parserEn.parse("2026-05-22 14:00", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
  EXPECT_TIME(r, 14, 0);
}

TEST_F(Chrono, EnMayDayTime) {
  auto r = parserEn.parse("May 22 at 9:00", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
  EXPECT_TIME(r, 9, 0);
}

TEST_F(Chrono, RuMayDayTime) {
  auto r = parserRu.parse(QString::fromUtf8("22 мая в 9:00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
  EXPECT_TIME(r, 9, 0);
}

// ── Ranges ──────────────────────────────────────────────────────────────
TEST_F(Chrono, RangeBareHours) {
  auto r = parserEn.parse("9-10", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 9, 0);
  EXPECT_EQ(r.end.time(), QTime(10, 0));
}

TEST_F(Chrono, RangePm) {
  auto r = parserEn.parse("2-3pm", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 14, 0);
  EXPECT_EQ(r.end.time(), QTime(15, 0));
}

TEST_F(Chrono, RangeFromTo) {
  auto r = parserEn.parse("from 14:00 to 15:00", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 14, 0);
  EXPECT_EQ(r.end.time(), QTime(15, 0));
}

TEST_F(Chrono, RuRangeS_Do) {
  auto r = parserRu.parse(QString::fromUtf8("с 14 до 15"), kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 14, 0);
  EXPECT_EQ(r.end.time(), QTime(15, 0));
}

TEST_F(Chrono, RangeWithDate) {
  auto r = parserEn.parse("tomorrow 9-10", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 9, 0);
  EXPECT_EQ(r.end.time(), QTime(10, 0));
}

TEST_F(Chrono, RuRangeWithDate) {
  auto r = parserRu.parse(QString::fromUtf8("завтра в 14:00-15:00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
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
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 2, 28);
}

TEST_F(Chrono, IsoDateLeap) {
  auto r = parserEn.parse("2024-02-29", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2024, 2, 29);
}

TEST_F(Chrono, MonthOverflow) {
  auto r = parserEn.parse("in 14 months", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2027, 7, 20);
}

TEST_F(Chrono, NegativeAgoCrossYear) {
  auto r = parserEn.parse("6 months ago", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2025, 11, 20);
}

// ── More relative variations ────────────────────────────────────────────
TEST_F(Chrono, EnInWk) {
  auto r = parserEn.parse("in 2 wk", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 6, 3);
}

TEST_F(Chrono, EnInD) {
  auto r = parserEn.parse("in 5 d", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
}

TEST_F(Chrono, RuMidWord) {
  auto r = parserRu.parse(QString::fromUtf8("через 2 нед"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 6, 3);
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
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 14, 0);
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
  EXPECT_OK(en);
  EXPECT_OK(ru);
  EXPECT_EQ(en.start.date(), QDate(2026, 5, 6));
  EXPECT_EQ(ru.start.date(), QDate(2026, 6, 5));
}

// ── Hour suffix variants ────────────────────────────────────────────────
TEST_F(Chrono, EnHourH) {
  auto r = parserEn.parse("16h", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 16, 0);
}

TEST_F(Chrono, RuHourFull) {
  auto r = parserRu.parse(QString::fromUtf8("16 часов"), kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 16, 0);
}

// ── Final assorted ─────────────────────────────────────────────────────
TEST_F(Chrono, EnTodaySlashTime) {
  auto r = parserEn.parse("today 9:15", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 20);
  EXPECT_TIME(r, 9, 15);
}

TEST_F(Chrono, RuPosleZavtra) {
  auto r = parserRu.parse(QString::fromUtf8("позавчера"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 18);
}

TEST_F(Chrono, EnNextFri) {
  auto r = parserEn.parse("next friday", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, EnNextSunday) {
  auto r = parserEn.parse("next sunday", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 24);
}

TEST_F(Chrono, RuVtornik) {
  auto r = parserRu.parse(QString::fromUtf8("вторник"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 26);
}

TEST_F(Chrono, RuChetverg) {
  auto r = parserRu.parse(QString::fromUtf8("четверг"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
}

TEST_F(Chrono, IsoTimeOnly) {
  auto r = parserEn.parse("08:45", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 8, 45);
  EXPECT_TRUE(r.hasTime);
}

TEST_F(Chrono, MidnightMarker) {
  auto r = parserEn.parse("00:00", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 0, 0);
  EXPECT_TRUE(r.hasTime);
}

// ── Space-separated time ────────────────────────────────────────────────
TEST_F(Chrono, SpaceTime1800) {
  auto r = parserEn.parse("18 00", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 18, 0);
  EXPECT_TRUE(r.hasTime);
}

TEST_F(Chrono, SpaceTimeWithMinutes) {
  auto r = parserEn.parse("9 30", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 9, 30);
}

TEST_F(Chrono, RuTomorrowSpaceTime) {
  auto r = parserRu.parse(QString::fromUtf8("завтра в 18 00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 18, 0);
}

TEST_F(Chrono, EnTomorrowSpaceTime) {
  auto r = parserEn.parse("tomorrow 14 30", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 14, 30);
}

TEST_F(Chrono, SpaceTimeRange) {
  auto r = parserEn.parse("18 00 - 19 00", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 18, 0);
  EXPECT_EQ(r.end.time(), QTime(19, 0));
}

TEST_F(Chrono, SpaceMinuteRequiresTwoDigits) {
  // "in 2 weeks" must not be eaten as 2:weeks. "in" routes via relative
  // prefix, but as a regression check ensure "2 weeks" alone never
  // resolves to a time.
  auto r = parserEn.parse("2 weeks", kRef);
  EXPECT_FALSE(r.ok);
}

// ── Reordered halves: date and time in any order, mention between (HEAP-104) ──
// A weekday and a clock time may be typed in either order, and a mention or
// connector may sit between them without breaking the parse.
TEST_F(Chrono, RuTimeBeforeWeekday) {
  auto r = parserRu.parse(QString::fromUtf8("13 00 понедельник"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_TIME(r, 13, 0);
  EXPECT_TRUE(r.hasTime);
}

TEST_F(Chrono, RuColonTimeBeforeWeekday) {
  auto r = parserRu.parse(QString::fromUtf8("13:00 понедельник"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_TIME(r, 13, 0);
}

TEST_F(Chrono, EnTimeBeforeWeekday) {
  auto r = parserEn.parse("9:30 friday", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
  EXPECT_TIME(r, 9, 30);
}

TEST_F(Chrono, EnTimeBeforeRelative) {
  auto r = parserEn.parse("2pm tomorrow", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 14, 0);
}

TEST_F(Chrono, RuMentionBetweenWeekdayAndTime) {
  // The @handle extractMeta leaves in the title must not break adjacency.
  auto r = parserRu.parse(QString::fromUtf8("понедельник @el 13 00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_TIME(r, 13, 0);
}

TEST_F(Chrono, RuMentionBetweenTimeAndWeekday) {
  auto r = parserRu.parse(QString::fromUtf8("13 00 @el понедельник"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_TIME(r, 13, 0);
}

TEST_F(Chrono, RuMentionBeforeBothHalves) {
  auto r = parserRu.parse(QString::fromUtf8("@el понедельник 13 00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_TIME(r, 13, 0);
}

TEST_F(Chrono, RuAtConnectorBridgedBetweenReordered) {
  // "в" connector between mention and time is bridged too.
  auto r = parserRu.parse(QString::fromUtf8("понедельник @el в 13 00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_TIME(r, 13, 0);
}

TEST_F(Chrono, ReorderedConsumedCoversBothHalves) {
  // The consumed span brackets both halves (and the noise between) so the
  // caller strips them together and the mention never lingers in the title.
  auto r = parserRu.parse(QString::fromUtf8("13 00 понедельник"), kRef);
  EXPECT_OK(r);
  EXPECT_EQ(r.consumed, QString::fromUtf8("13 00 понедельник"));
}

TEST_F(Chrono, RealWordGapIsNotBridged) {
  // A real title word between the two halves must NOT be swallowed: the time
  // is left unparsed rather than eating "отчет".
  auto r = parserRu.parse(QString::fromUtf8("понедельник отчет 13 00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_FALSE(r.hasTime);
}

TEST_F(Chrono, NumberGapIsNotBridged) {
  // A bare number between the halves is content (a ticket id / quantity), not
  // noise — it must not be absorbed into the consumed datetime span.
  auto r = parserEn.parse("monday 42 at 3pm", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_FALSE(r.hasTime);
  EXPECT_EQ(r.consumed, QString("monday"));
}

TEST_F(Chrono, RuNumberGapIsNotBridged) {
  auto r = parserRu.parse(QString::fromUtf8("понедельник 42 13 00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
  EXPECT_FALSE(r.hasTime);
  EXPECT_EQ(r.consumed, QString::fromUtf8("понедельник"));
}

// ── Relative clock times and named times (audit A7 / B13) ────────────────
// A separate fixture named after the class under test.
class ChronoParserTest : public ::testing::Test {
 protected:
  ChronoParser parser{QLocale(QLocale::English, QLocale::UnitedStates)};
};

TEST_F(ChronoParserTest, Parse_RuInTwoHours_ReturnsMomentTwoHoursAhead) {
  const QString text = QString::fromUtf8("Deploy через 2 часа");
  auto r = parser.parse(text, kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 20);
  EXPECT_TIME(r, 12, 0);
  EXPECT_TRUE(r.hasTime);
  EXPECT_EQ(text.left(r.startOffset).trimmed(), QStringLiteral("Deploy"));
}

TEST_F(ChronoParserTest, Parse_EnInTwoHoursPastMidnight_RollsToNextDay) {
  auto r = parser.parse("ship in 3 hours", QDateTime(kRefDate, QTime(22, 30)));
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 1, 30);
}

TEST_F(ChronoParserTest, Parse_InAnHourAndInMinutes_ReturnsClockOffset) {
  auto a = parser.parse("call in an hour", kRef);
  EXPECT_OK(a);
  EXPECT_TIME(a, 11, 0);
  auto b = parser.parse(QString::fromUtf8("через 30 минут"), kRef);
  EXPECT_OK(b);
  EXPECT_TIME(b, 10, 30);
}

TEST_F(ChronoParserTest, Parse_RuInAWeekWithoutNumber_ReturnsNextWeek) {
  auto r = parser.parse(QString::fromUtf8("отчёт через неделю"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 27);
  EXPECT_FALSE(r.hasTime);
}

TEST_F(ChronoParserTest, Parse_NoonAndEod_ReturnNamedTimesToday) {
  auto noon = parser.parse("lunch at noon", kRef);
  EXPECT_OK(noon);
  EXPECT_DATE(noon, 2026, 5, 20);
  EXPECT_TIME(noon, 12, 0);
  auto eod = parser.parse("report eod", kRef);
  EXPECT_OK(eod);
  EXPECT_TIME(eod, 18, 0);
  auto friEod = parser.parse("report friday eod", kRef);
  EXPECT_OK(friEod);
  EXPECT_DATE(friEod, 2026, 5, 22);
  EXPECT_TIME(friEod, 18, 0);
}

TEST_F(ChronoParserTest, Parse_EndOfMonth_ReturnsLastDayOfMonth) {
  auto r = parser.parse("invoice end of month", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 31);
  auto ru = parser.parse(QString::fromUtf8("счёт конец месяца"), kRef);
  EXPECT_OK(ru);
  EXPECT_DATE(ru, 2026, 5, 31);
}

TEST_F(ChronoParserTest, Parse_PrepositionBeforeDate_IsConsumedWithIt) {
  const QString text = QStringLiteral("ship on friday");
  auto r = parser.parse(text, kRef);
  EXPECT_OK(r);
  EXPECT_EQ(text.left(r.startOffset).trimmed(), QStringLiteral("ship"));
}

TEST_F(ChronoParserTest, Parse_InvalidIsoDate_IsNotReadAsTimeRange) {
  auto r = parser.parse("2026-13-01", kRef);
  EXPECT_FALSE(r.ok);
}

// ── Extended vocabulary: parts of the day, weekday cases, the weekend ─────
TEST_F(Chrono, RuTomorrowMorning) {
  auto r = parserRu.parse(QString::fromUtf8("созвон завтра утром"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 9, 0);
  EXPECT_TRUE(r.hasTime);
}

TEST_F(Chrono, RuTodayEvening) {
  auto r = parserRu.parse(QString::fromUtf8("сегодня вечером"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 20);
  EXPECT_TIME(r, 19, 0);
}

TEST_F(Chrono, RuDativeWeekday) {
  // "к пятнице" — the case a deadline is written in.
  auto r = parserRu.parse(QString::fromUtf8("отчёт к пятнице"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
}

TEST_F(Chrono, RuGenitiveWeekday) {
  auto r = parserRu.parse(QString::fromUtf8("до понедельника"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);
}

TEST_F(Chrono, RuWeekend) {
  auto r = parserRu.parse(QString::fromUtf8("на выходных"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 23);
}

TEST_F(Chrono, EnTomorrowEvening) {
  auto r = parserEn.parse("call mom tomorrow evening", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 19, 0);
}

TEST_F(Chrono, EnWeekend) {
  auto r = parserEn.parse("clean up on the weekend", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 23);
}

TEST_F(Chrono, RuEveryWorkingDay) {
  for(const char* text : {"дейли каждый будний день в 10:00", "по будням в 10:00", "каждый рабочий день в 10:00"}) {
    auto r = parserRu.parse(QString::fromUtf8(text), kRef);
    EXPECT_OK(r);
    EXPECT_EQ(r.recurrence, QStringLiteral("every:weekday")) << text;
    EXPECT_TIME(r, 10, 0);
  }
}

TEST_F(Chrono, OneOnOneIsNotATime) {
  auto r = parserRu.parse(QString::fromUtf8("1:1 с Анной в четверг в 12:00"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 12, 0);
}

// ── The audit's TASKS-14: a bare time that has passed means tomorrow ─────

namespace {
// Wednesday evening, after most times of the day have gone by.
const QDateTime kLate(QDate(2026, 5, 20), QTime(23, 49));
}  // namespace

TEST_F(Chrono, APassedBareTimeIsTomorrow) {
  auto r = parserEn.parse("call mom at 5", kLate);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 5, 0);

  r = parserEn.parse("lunch at noon", kLate);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);

  r = parserRu.parse(QString::fromUtf8("отчёт к 18:00"), kLate);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 18, 0);
}

TEST_F(Chrono, AComingBareTimeStaysToday) {
  auto r = parserEn.parse("call mom at 17:00", kRef);  // 10:00
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 20);
}

TEST_F(Chrono, AnExplicitTodayIsKeptEvenWhenPassed) {
  auto r = parserEn.parse("today at 9am", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 20) << "the user said today";
}

TEST_F(Chrono, ARecurringTimeThatPassedStartsAtTheNextOccurrence) {
  // Wednesday 10:30: today's 10:00 has gone, Thursday is the next workday.
  auto r = parserEn.parse("standup every weekday 10:00", QDateTime(kRefDate, QTime(10, 30)));
  EXPECT_OK(r);
  EXPECT_EQ(r.recurrence, QStringLiteral("every:weekday"));
  EXPECT_DATE(r, 2026, 5, 21);
  // Friday evening → Monday.
  r = parserEn.parse("standup every weekday 10:00", QDateTime(QDate(2026, 5, 22), QTime(18, 0)));
  EXPECT_DATE(r, 2026, 5, 25);
  // Before 10:00 it is still today.
  r = parserEn.parse("standup every weekday 10:00", QDateTime(kRefDate, QTime(9, 0)));
  EXPECT_DATE(r, 2026, 5, 20);
}

// ── TASKS-24: phrases that went unparsed or stayed in the title ─────────

TEST_F(Chrono, HalfAnHour) {
  auto r = parserRu.parse(QString::fromUtf8("перезвонить через полчаса"), kRef);
  EXPECT_OK(r);
  EXPECT_TRUE(r.hasTime);
  EXPECT_EQ(r.start, kRef.addSecs(30 * 60));
  EXPECT_EQ(r.consumed, QString::fromUtf8("через полчаса"));

  r = parserEn.parse("ping in half an hour", kRef);
  EXPECT_OK(r);
  EXPECT_EQ(r.start, kRef.addSecs(30 * 60));
}

TEST_F(Chrono, NextWeekAndNextMonth) {
  auto r = parserEn.parse("plan the offsite next week", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);  // Monday
  EXPECT_FALSE(r.hasTime);
  EXPECT_EQ(r.consumed, QStringLiteral("next week"));

  r = parserRu.parse(QString::fromUtf8("отпуск на следующей неделе"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 25);

  r = parserEn.parse("renew cert next month", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 6, 1);
}

TEST_F(Chrono, DayPartsAreTimesAndLeaveTheTitle) {
  auto r = parserEn.parse("deploy tonight", kRef);
  EXPECT_OK(r);
  EXPECT_TRUE(r.hasTime);
  EXPECT_TIME(r, 20, 0);
  EXPECT_EQ(r.consumed, QStringLiteral("tonight"));

  r = parserEn.parse("call Bob tomorrow morning", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 9, 0);
  EXPECT_EQ(r.consumed, QStringLiteral("tomorrow morning"));

  r = parserRu.parse(QString::fromUtf8("позвонить маме завтра вечером"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 19, 0);
  EXPECT_EQ(r.consumed, QString::fromUtf8("завтра вечером"));

  r = parserRu.parse(QString::fromUtf8("утром проверить логи"), kRef);  // 10:00: morning passed
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 21);
  EXPECT_TIME(r, 9, 0);

  r = parserEn.parse("review PRs in the evening", kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 19, 0);
  EXPECT_EQ(r.consumed, QStringLiteral("in the evening"));
}

TEST_F(Chrono, MonthlyRecurrence) {
  auto r = parserEn.parse("pay rent every month on the 15th", kRef);
  EXPECT_OK(r);
  EXPECT_EQ(r.recurrence, QStringLiteral("every:month:15"));
  EXPECT_DATE(r, 2026, 6, 15);  // the 15th of May has passed
  EXPECT_EQ(r.consumed, QStringLiteral("every month on the 15th"));

  r = parserEn.parse("invoice monthly", kRef);
  EXPECT_OK(r);
  EXPECT_EQ(r.recurrence, QStringLiteral("every:month:20"));
  EXPECT_DATE(r, 2026, 5, 20);

  r = parserRu.parse(QString::fromUtf8("отчёт каждый месяц"), kRef);
  EXPECT_OK(r);
  EXPECT_EQ(r.recurrence, QStringLiteral("every:month:20"));

  r = parserRu.parse(QString::fromUtf8("аренда каждое 25 число"), kRef);
  EXPECT_OK(r);
  EXPECT_EQ(r.recurrence, QStringLiteral("every:month:25"));
  EXPECT_DATE(r, 2026, 5, 25);
}

// TASKS-8 (audit 2026-09-30): version and section numbers are not dates.
// "release 1.2.3" got a due date in 2003 and lost "1.2.3" from its title.
TEST_F(Chrono, VersionNumbersAreNotDates) {
  for(const char* text : {"release 1.2.3 notes",
                          "bump qt to 6.9.1",
                          "read section 4.2 of the spec",
                          "upgrade node 20.11",
                          "ship 1.2.3.4",
                          "bump to 6.10.12",
                          "version 2.1 changelog"}) {
    const auto r = parserEn.parse(QString::fromUtf8(text), kRef);
    EXPECT_FALSE(r.ok) << text << " -> " << r.consumed.toStdString();
  }
  EXPECT_FALSE(parserRu.parse(QString::fromUtf8("прочитать раздел 4.2"), kRef).ok);
}

// The guard leaves real dotted dates alone, including a two-digit year in the
// recent past and a date after a version.
TEST_F(Chrono, DottedDatesStillParseNextToVersionGuard) {
  auto r = parserEn.parse("ship it by 22.05", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
  r = parserRu.parse(QString::fromUtf8("сдать отчёт 15.10.25"), kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2025, 10, 15);
  r = parserEn.parse("release 1.2.3 on 22.05", kRef);
  EXPECT_OK(r);
  EXPECT_DATE(r, 2026, 5, 22);
  EXPECT_EQ(r.consumed, QStringLiteral("on 22.05"));
}

// ── Identifiers with dashed numbers are not times (DATA-4) ────────────────
TEST_F(Chrono, EnDashedIdentifierIsNotATimeRange) {
  for(const char* s : {"merge feature-12-3", "kill-1-3", "fix-2-4 login", "bump v1-2", "auth-v2"}) {
    auto r = parserEn.parse(QString::fromUtf8(s), kRef);
    EXPECT_FALSE(r.ok) << s;
  }
}

TEST_F(Chrono, RuDashedIdentifierIsNotATimeRange) {
  for(const char* s : {"смёржить фича-12-3", "починить баг-2-4 логин", "обновить v1-2"}) {
    auto r = parserRu.parse(QString::fromUtf8(s), kRef);
    EXPECT_FALSE(r.ok) << s;
  }
}

TEST_F(Chrono, SpacedTimeRangeStillParsesNextToIdentifier) {
  auto r = parserEn.parse(QString::fromUtf8("merge feature-12 at 2-3pm"), kRef);
  EXPECT_OK(r);
  EXPECT_TIME(r, 14, 0);
  EXPECT_TRUE(r.hasTime);
  auto ru = parserRu.parse(QString::fromUtf8("созвон по фича-12 в 9-10"), kRef);
  EXPECT_OK(ru);
  EXPECT_TIME(ru, 9, 0);
}
