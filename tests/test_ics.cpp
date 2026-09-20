// Reading and writing .ics.
//
// Every meeting heap holds arrives from somewhere else — Google, Outlook, a
// conference's "add to calendar" link — and RFC 5545 is the only thing all of
// them agree on. The format's traps each produce a bug that looks like data
// loss: a folded line turns a long summary into nonsense, an exclusive DTEND
// read inclusively makes every all-day event a day too long, and a VALARM
// inside a VEVENT ends the event early if the first END: is trusted.

#include "cal/IcsCodec.h"

#include <gtest/gtest.h>

using heap::cal::IcsImport;
using heap::cal::parseIcs;
using heap::cal::toIcs;

namespace {

// A minimal document around one VEVENT body.
QString wrap(const QString& body) {
  return QStringLiteral("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n") + body +
         QStringLiteral("\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
}

CalEvent one(const QString& body) {
  const IcsImport in = parseIcs(wrap(body));
  return in.events.isEmpty() ? CalEvent{} : in.events.first();
}

}  // namespace

// ── Line structure ──

TEST(Ics, AFoldedLineIsJoinedBeforeItIsRead) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nSUMMARY:A very long title that\r\n  continues here"));

  EXPECT_EQ(e.title, QStringLiteral("A very long title that continues here"));
}

TEST(Ics, ATabContinuesALineToo) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nSUMMARY:split\r\n\there"));

  EXPECT_EQ(e.title, QStringLiteral("splithere"));
}

// Plenty of files in the wild use bare LF.
TEST(Ics, BareLineFeedsWork) {
  const IcsImport in =
      parseIcs(QStringLiteral("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:a\nDTSTART:20260921T100000\nSUMMARY:x\nEND:VEVENT\nEND:VCALENDAR\n"));

  ASSERT_EQ(in.events.size(), 1);
  EXPECT_EQ(in.events.first().title, QStringLiteral("x"));
}

TEST(Ics, EscapesAreUndoneOnRead) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nSUMMARY:Standup\\, daily\\; and long\\nsecond line"));

  EXPECT_EQ(e.title, QStringLiteral("Standup, daily; and long\nsecond line"));
}

TEST(Ics, AParameterIsNotMistakenForTheValue) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART;VALUE=DATE:20260921\r\nSUMMARY:x"));

  EXPECT_TRUE(e.allDay);
  EXPECT_EQ(e.date, QDate(2026, 9, 21));
}

// A colon inside a quoted parameter does not end the name part.
TEST(Ics, AColonInsideAQuotedParameterIsNotTheSeparator) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART;TZID=\"Weird:Zone\":20260921T100000\r\nSUMMARY:x"));

  EXPECT_EQ(e.date, QDate(2026, 9, 21));
  EXPECT_NEAR(e.start, 10.0, 0.001);
}

// ── Times ──

TEST(Ics, AFloatingTimeIsTakenAsWritten) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T093000\r\nDTEND:20260921T100000\r\nSUMMARY:x"));

  EXPECT_EQ(e.date, QDate(2026, 9, 21));
  EXPECT_NEAR(e.start, 9.5, 0.001);
  EXPECT_NEAR(e.end, 10.0, 0.001);
}

// A UTC stamp shown at its literal hour would put a 14:00Z meeting at 14:00
// everywhere on earth.
TEST(Ics, AUtcTimeIsConvertedToLocal) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T120000Z\r\nDTEND:20260921T130000Z\r\nSUMMARY:x"));

  const QDateTime expected = QDateTime(QDate(2026, 9, 21), QTime(12, 0), QTimeZone::utc()).toLocalTime();
  EXPECT_EQ(e.date, expected.date());
  EXPECT_NEAR(e.start, expected.time().hour() + expected.time().minute() / 60.0, 0.001);
}

// An unknown zone is floating local rather than dropped: better to show the
// meeting at the hour written down than to lose it.
TEST(Ics, AnUnknownTimeZoneFallsBackToTheWrittenHour) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART;TZID=Mars/Olympus:20260921T100000\r\nSUMMARY:x"));

  EXPECT_EQ(e.date, QDate(2026, 9, 21));
  EXPECT_NEAR(e.start, 10.0, 0.001);
}

TEST(Ics, AMissingEndMeansAnHour) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nSUMMARY:x"));

  EXPECT_NEAR(e.start, 10.0, 0.001);
  EXPECT_NEAR(e.end, 11.0, 0.001);
  EXPECT_FALSE(e.endDate.isValid());
}

// The whole reason spans exist: a DTEND on the following day is an event that
// crosses midnight, not a broken one.
TEST(Ics, ATimedEventMayCrossMidnight) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T220000\r\nDTEND:20260922T020000\r\nSUMMARY:x"));

  EXPECT_EQ(e.date, QDate(2026, 9, 21));
  EXPECT_EQ(e.endDate, QDate(2026, 9, 22));
  EXPECT_NEAR(e.start, 22.0, 0.001);
  EXPECT_NEAR(e.end, 2.0, 0.001);
}

// ── DURATION ──

TEST(Ics, ADurationInHoursIsUnderstood) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nDURATION:PT2H\r\nSUMMARY:x"));

  EXPECT_NEAR(e.end, 12.0, 0.001);
}

TEST(Ics, ADurationInMinutesIsUnderstood) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nDURATION:PT30M\r\nSUMMARY:x"));

  EXPECT_NEAR(e.end, 10.5, 0.001);
}

TEST(Ics, AMixedDurationIsUnderstood) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nDURATION:PT1H30M\r\nSUMMARY:x"));

  EXPECT_NEAR(e.end, 11.5, 0.001);
}

TEST(Ics, ADurationMayCrossMidnight) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T230000\r\nDURATION:PT3H\r\nSUMMARY:x"));

  EXPECT_EQ(e.endDate, QDate(2026, 9, 22));
  EXPECT_NEAR(e.end, 2.0, 0.001);
}

// Both present is a contradiction the spec forbids; DTEND is the more explicit
// of the two, so it wins rather than the file being rejected.
TEST(Ics, DtEndBeatsDuration) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nDTEND:20260921T103000\r\nDURATION:PT5H\r\nSUMMARY:x"));

  EXPECT_NEAR(e.end, 10.5, 0.001);
}

// ── All-day ──

TEST(Ics, AnAllDayEventHasNoHours) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART;VALUE=DATE:20260921\r\nSUMMARY:holiday"));

  EXPECT_TRUE(e.allDay);
  EXPECT_NEAR(e.start, 0.0, 0.001);
  EXPECT_NEAR(e.end, 24.0, 0.001);
}

// The classic .ics bug. DTEND is exclusive for a DATE value, so 21 to 24 is
// three days ending on the 23rd. Reading it inclusively makes every imported
// all-day event one day too long.
TEST(Ics, AnAllDayEndDateIsExclusive) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART;VALUE=DATE:20260921\r\nDTEND;VALUE=DATE:20260924\r\nSUMMARY:trip"));

  EXPECT_EQ(e.date, QDate(2026, 9, 21));
  EXPECT_EQ(e.endDate, QDate(2026, 9, 23));
}

TEST(Ics, AOneDayAllDayEventHasNoEndDate) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART;VALUE=DATE:20260921\r\nDTEND;VALUE=DATE:20260922\r\nSUMMARY:x"));

  EXPECT_FALSE(e.endDate.isValid());
}

// ── Recurrence ──

TEST(Ics, ARecurrenceRuleIsKept) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nRRULE:FREQ=WEEKLY;BYDAY=MO\r\nSUMMARY:x"));

  EXPECT_EQ(e.rrule, QStringLiteral("FREQ=WEEKLY;BYDAY=MO"));
}

// A rule heap does not model must not take the event down with it: dropping it
// would hide something the user put in their calendar.
TEST(Ics, AnUnsupportedRuleImportsASingleEventAndWarns) {
  const IcsImport in = parseIcs(wrap(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nRRULE:FREQ=SECONDLY\r\nSUMMARY:x")));

  ASSERT_EQ(in.events.size(), 1);
  EXPECT_TRUE(in.events.first().rrule.isEmpty());
  EXPECT_FALSE(in.warnings.isEmpty());
}

TEST(Ics, ExdatesOnOneLineAreAllRead) {
  const CalEvent e =
      one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nRRULE:FREQ=WEEKLY\r\nEXDATE:20260928T100000,20261005T100000\r\nSUMMARY:x"));

  ASSERT_EQ(e.exdates.size(), 2);
  EXPECT_EQ(e.exdates.at(0), QDate(2026, 9, 28));
  EXPECT_EQ(e.exdates.at(1), QDate(2026, 10, 5));
}

TEST(Ics, SeveralExdateLinesAccumulate) {
  const CalEvent e = one(QStringLiteral(
      "UID:a\r\nDTSTART:20260921T100000\r\nRRULE:FREQ=WEEKLY\r\nEXDATE:20260928T100000\r\nEXDATE:20261005T100000\r\nSUMMARY:x"));

  EXPECT_EQ(e.exdates.size(), 2);
}

// An override names the occurrence it replaces and points at the master, which
// is the event sharing its UID.
TEST(Ics, ARecurrenceIdBecomesAnOverride) {
  const CalEvent e = one(QStringLiteral("UID:series-1\r\nRECURRENCE-ID:20260928T100000\r\nDTSTART:20260930T100000\r\nSUMMARY:moved"));

  EXPECT_EQ(e.masterId, QStringLiteral("series-1"));
  EXPECT_EQ(e.originalDate, QDate(2026, 9, 28));
  EXPECT_NE(e.id, QStringLiteral("series-1")) << "an override cannot share the master's id";
}

// ── Structure and robustness ──

TEST(Ics, ACancelledEventIsSkipped) {
  const IcsImport in = parseIcs(wrap(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nSTATUS:CANCELLED\r\nSUMMARY:x")));

  EXPECT_TRUE(in.events.isEmpty());
  EXPECT_EQ(in.skipped, 1);
}

// The first END: inside a VEVENT belongs to the VALARM, not the event.
TEST(Ics, AnAlarmInsideAnEventDoesNotEndIt) {
  const CalEvent e = one(QStringLiteral(
      "UID:a\r\nDTSTART:20260921T100000\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT10M\r\nEND:VALARM\r\nSUMMARY:after the alarm"));

  EXPECT_EQ(e.title, QStringLiteral("after the alarm"));
}

TEST(Ics, TimezoneBlocksDoNotBecomeEvents) {
  const QString doc = QStringLiteral(
      "BEGIN:VCALENDAR\r\nBEGIN:VTIMEZONE\r\nTZID:Europe/Moscow\r\nBEGIN:STANDARD\r\nDTSTART:19700101T000000\r\n"
      "END:STANDARD\r\nEND:VTIMEZONE\r\nBEGIN:VEVENT\r\nUID:a\r\nDTSTART:20260921T100000\r\nSUMMARY:x\r\n"
      "END:VEVENT\r\nEND:VCALENDAR\r\n");

  const IcsImport in = parseIcs(doc);

  ASSERT_EQ(in.events.size(), 1);
  EXPECT_EQ(in.events.first().title, QStringLiteral("x"));
}

TEST(Ics, ATodoIsNotAnEvent) {
  const QString doc = QStringLiteral(
      "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:t\r\nDTSTART:20260921T100000\r\nSUMMARY:a task\r\nEND:VTODO\r\n"
      "END:VCALENDAR\r\n");

  EXPECT_TRUE(parseIcs(doc).events.isEmpty());
}

TEST(Ics, AnEventWithNoStartIsSkipped) {
  const IcsImport in = parseIcs(wrap(QStringLiteral("UID:a\r\nSUMMARY:when?")));

  EXPECT_TRUE(in.events.isEmpty());
  EXPECT_EQ(in.skipped, 1);
}

// A truncated download is a truncated file, not an event.
TEST(Ics, AnUnterminatedEventIsSkipped) {
  const IcsImport in = parseIcs(QStringLiteral("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nDTSTART:20260921T100000\r\n"));

  EXPECT_TRUE(in.events.isEmpty());
  EXPECT_EQ(in.skipped, 1);
}

TEST(Ics, GarbageParsesToNothing) {
  EXPECT_TRUE(parseIcs(QStringLiteral("not a calendar at all")).events.isEmpty());
  EXPECT_TRUE(parseIcs(QString()).events.isEmpty());
  EXPECT_TRUE(parseIcs(QStringLiteral(":::\r\n;;;\r\nBEGIN:\r\nEND:")).events.isEmpty());
}

// Two events with no UID must not collide, or importing a file would silently
// keep one of them.
TEST(Ics, EventsWithoutUidsGetDistinctIds) {
  const QString doc = QStringLiteral(
      "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:20260921T100000\r\nSUMMARY:one\r\nEND:VEVENT\r\n"
      "BEGIN:VEVENT\r\nDTSTART:20260922T100000\r\nSUMMARY:two\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");

  const IcsImport in = parseIcs(doc);

  ASSERT_EQ(in.events.size(), 2);
  EXPECT_NE(in.events.at(0).id, in.events.at(1).id);
}

TEST(Ics, LocationBecomesTheContext) {
  const CalEvent e = one(QStringLiteral("UID:a\r\nDTSTART:20260921T100000\r\nLOCATION:Room 3\r\nSUMMARY:x"));

  EXPECT_EQ(e.context, QStringLiteral("Room 3"));
}

// heap has nowhere to put a description; saying so once is honest, saying so
// per event would bury the real warnings.
TEST(Ics, DescriptionIsReportedOnceForTheWholeFile) {
  const QString doc = QStringLiteral(
      "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nDTSTART:20260921T100000\r\nDESCRIPTION:notes\r\nSUMMARY:one\r\n"
      "END:VEVENT\r\nBEGIN:VEVENT\r\nUID:b\r\nDTSTART:20260922T100000\r\nDESCRIPTION:more\r\nSUMMARY:two\r\n"
      "END:VEVENT\r\nEND:VCALENDAR\r\n");

  const IcsImport in = parseIcs(doc);

  EXPECT_EQ(in.events.size(), 2);
  EXPECT_EQ(in.warnings.size(), 1);
}

// ── Writing ──

namespace {

CalEvent timed() {
  CalEvent e;
  e.id = QStringLiteral("ev-1");
  e.title = QStringLiteral("Design review");
  e.date = QDate(2026, 9, 21);
  e.start = 14.0;
  e.end = 15.5;
  return e;
}

}  // namespace

TEST(Ics, AWrittenDocumentIsWellFormed) {
  const QString doc = toIcs({timed()});

  EXPECT_TRUE(doc.startsWith(QStringLiteral("BEGIN:VCALENDAR")));
  EXPECT_TRUE(doc.contains(QStringLiteral("VERSION:2.0")));
  EXPECT_TRUE(doc.contains(QStringLiteral("BEGIN:VEVENT")));
  EXPECT_TRUE(doc.trimmed().endsWith(QStringLiteral("END:VCALENDAR")));
  EXPECT_TRUE(doc.contains(QStringLiteral("\r\n"))) << "CRLF, per the spec";
}

TEST(Ics, ALongSummaryIsFolded) {
  CalEvent e = timed();
  e.title = QString(200, QLatin1Char('x'));

  for(const QString& line : toIcs({e}).split(QStringLiteral("\r\n"))) {
    EXPECT_LE(line.toUtf8().size(), 75) << line.toStdString();
  }
}

// Folding is by octet, so a Cyrillic summary must not be split mid-character.
TEST(Ics, AFoldedNonAsciiSummarySurvives) {
  CalEvent e = timed();
  e.title = QString(60, QChar(0x0434));  // "д" repeated

  const CalEvent back = parseIcs(toIcs({e})).events.value(0);

  EXPECT_EQ(back.title, e.title);
}

TEST(Ics, AnAllDayEventIsWrittenWithAnExclusiveEnd) {
  CalEvent e = timed();
  e.allDay = true;
  e.start = 0;
  e.end = 24;
  e.endDate = QDate(2026, 9, 23);

  const QString doc = toIcs({e});

  EXPECT_TRUE(doc.contains(QStringLiteral("DTSTART;VALUE=DATE:20260921")));
  EXPECT_TRUE(doc.contains(QStringLiteral("DTEND;VALUE=DATE:20260924"))) << doc.toStdString();
}

// ── Round trips ──

TEST(Ics, AnOrdinaryEventSurvivesARoundTrip) {
  const CalEvent e = timed();

  const CalEvent back = parseIcs(toIcs({e})).events.value(0);

  EXPECT_EQ(back.id, e.id);
  EXPECT_EQ(back.title, e.title);
  EXPECT_EQ(back.date, e.date);
  EXPECT_NEAR(back.start, e.start, 0.001);
  EXPECT_NEAR(back.end, e.end, 0.001);
  EXPECT_FALSE(back.allDay);
}

TEST(Ics, AnAllDayEventSurvivesARoundTrip) {
  CalEvent e = timed();
  e.allDay = true;
  e.start = 0;
  e.end = 24;

  const CalEvent back = parseIcs(toIcs({e})).events.value(0);

  EXPECT_TRUE(back.allDay);
  EXPECT_EQ(back.date, e.date);
  EXPECT_FALSE(back.endDate.isValid());
}

TEST(Ics, AMultiDayAllDayEventSurvivesARoundTrip) {
  CalEvent e = timed();
  e.allDay = true;
  e.start = 0;
  e.end = 24;
  e.endDate = QDate(2026, 9, 25);

  const CalEvent back = parseIcs(toIcs({e})).events.value(0);

  EXPECT_TRUE(back.allDay);
  EXPECT_EQ(back.date, e.date);
  EXPECT_EQ(back.endDate, e.endDate);
}

TEST(Ics, ACrossMidnightEventSurvivesARoundTrip) {
  CalEvent e = timed();
  e.start = 22.0;
  e.end = 2.0;
  e.endDate = QDate(2026, 9, 22);

  const CalEvent back = parseIcs(toIcs({e})).events.value(0);

  EXPECT_EQ(back.date, e.date);
  EXPECT_EQ(back.endDate, e.endDate);
  EXPECT_NEAR(back.start, 22.0, 0.001);
  EXPECT_NEAR(back.end, 2.0, 0.001);
}

TEST(Ics, ARecurringEventSurvivesARoundTrip) {
  CalEvent e = timed();
  e.rrule = QStringLiteral("FREQ=WEEKLY;INTERVAL=2");
  e.exdates = {QDate(2026, 10, 5)};

  const CalEvent back = parseIcs(toIcs({e})).events.value(0);

  EXPECT_EQ(back.rrule, e.rrule);
  ASSERT_EQ(back.exdates.size(), 1);
  EXPECT_EQ(back.exdates.at(0), QDate(2026, 10, 5));
}

// A title with the characters the format uses for its own punctuation.
TEST(Ics, APunctuatedTitleSurvivesARoundTrip) {
  CalEvent e = timed();
  e.title = QStringLiteral("Review: schema, rank; and \\paths\\");

  EXPECT_EQ(parseIcs(toIcs({e})).events.value(0).title, e.title);
}

TEST(Ics, AnEmptyListWritesAnEmptyCalendar) {
  const IcsImport back = parseIcs(toIcs({}));

  EXPECT_TRUE(back.events.isEmpty());
  EXPECT_EQ(back.skipped, 0);
}

// Importing the same file twice is the commonest thing anyone does with one,
// and the UID is what makes it recognisable as a duplicate rather than a
// second copy.
TEST(Ics, TheSameFileTwiceYieldsTheSameIds) {
  const QString doc = toIcs({timed()});

  EXPECT_EQ(parseIcs(doc).events.value(0).id, parseIcs(doc).events.value(0).id);
}
