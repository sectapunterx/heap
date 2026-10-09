// One line of task input, split into "when" and "due" (APP-245) and an
// estimate (APP-246). A pure function of the text and `now`.
#include "capture/CaptureParse.h"
#include "chrono/ChronoParser.h"

#include <QDate>
#include <QDateTime>
#include <QLocale>
#include <QTime>

#include <gtest/gtest.h>

using heap::capture::parse;
using heap::capture::Parsed;

namespace {

const QDateTime kNow(QDate(2026, 5, 20), QTime(10, 0));  // Wednesday 10:00

class Capture : public ::testing::Test {
 protected:
  heap::chrono::ChronoParser chrono{QLocale(QLocale::Russian, QLocale::Russia)};

  Parsed p(const QString& text, const QStringList& rejected = {}) {
    return parse(text, chrono, kNow, rejected);
  }
};

}  // namespace

TEST_F(Capture, ADateWithNoDeadlineWordIsWhen) {
  const Parsed r = p(QStringLiteral("позвонить Ане завтра в 15:00"));
  EXPECT_EQ(r.title, QStringLiteral("позвонить Ане"));
  EXPECT_EQ(r.when, QDateTime(QDate(2026, 5, 21), QTime(15, 0)));
  EXPECT_TRUE(r.whenHasTime);
  EXPECT_FALSE(r.due.isValid()) << "one date is no longer both";
}

TEST_F(Capture, ADateAfterDoIsTheDeadline) {
  const Parsed r = p(QStringLiteral("отчёт до пятницы"));
  EXPECT_EQ(r.title, QStringLiteral("отчёт"));
  EXPECT_EQ(r.due.date(), QDate(2026, 5, 22));
  EXPECT_FALSE(r.dueHasTime);
  EXPECT_FALSE(r.when.isValid());
  ASSERT_EQ(r.spans.size(), 1);
  EXPECT_EQ(r.spans.at(0).kind, QStringLiteral("due"));
  EXPECT_EQ(r.spans.at(0).text, QStringLiteral("до пятницы"));
}

TEST_F(Capture, WhenAndDueInOneLine) {
  const Parsed r = p(QStringLiteral("сделать в понедельник, сдать до пятницы"));
  EXPECT_EQ(r.when.date(), QDate(2026, 5, 25));
  EXPECT_EQ(r.due.date(), QDate(2026, 5, 22));
  EXPECT_EQ(r.title, QStringLiteral("сделать, сдать"));
}

TEST_F(Capture, TheDeadlineMayComeFirst) {
  const Parsed r = p(QStringLiteral("до пт ревью, завтра начать"));
  EXPECT_EQ(r.due.date(), QDate(2026, 5, 22));
  EXPECT_EQ(r.when.date(), QDate(2026, 5, 21));
  EXPECT_EQ(r.title, QStringLiteral("ревью, начать"));
}

TEST_F(Capture, EnglishDueAndBy) {
  heap::chrono::ChronoParser en{QLocale(QLocale::English, QLocale::UnitedStates)};
  const Parsed a = parse(QStringLiteral("write spec due fri"), en, kNow);
  EXPECT_EQ(a.title, QStringLiteral("write spec"));
  EXPECT_EQ(a.due.date(), QDate(2026, 5, 22));
  const Parsed b = parse(QStringLiteral("tomorrow 9am start, ship by monday"), en, kNow);
  EXPECT_EQ(b.when, QDateTime(QDate(2026, 5, 21), QTime(9, 0)));
  EXPECT_EQ(b.due.date(), QDate(2026, 5, 25));
}

TEST_F(Capture, ADeadlineWordInsideAWordIsNotOne) {
  // "Подробно" ends in "до", "Скоро" is not "к": only a whole word counts.
  const Parsed r = p(QStringLiteral("разобрать подробно завтра"));
  EXPECT_TRUE(r.when.isValid());
  EXPECT_FALSE(r.due.isValid());
}

TEST_F(Capture, ASecondUnmarkedDateStaysInTheTitle) {
  const Parsed r = p(QStringLiteral("перенести с завтра на пятницу"));
  EXPECT_TRUE(r.when.isValid());
  EXPECT_FALSE(r.due.isValid());
  EXPECT_EQ(r.spans.size(), 1) << "nothing is guessed from the second date";
}

TEST_F(Capture, ARejectedPhraseStaysWords) {
  const Parsed first = p(QStringLiteral("Обзор пятницы"));
  ASSERT_EQ(first.spans.size(), 1);
  const Parsed again = p(QStringLiteral("Обзор пятницы"), {first.spans.at(0).text});
  EXPECT_EQ(again.title, QStringLiteral("Обзор пятницы"));
  EXPECT_FALSE(again.when.isValid());
  EXPECT_TRUE(again.spans.isEmpty());
}

TEST_F(Capture, ATypoIsNotGuessed) {
  const Parsed r = p(QStringLiteral("купить хлеб завтар"));
  EXPECT_EQ(r.title, QStringLiteral("купить хлеб завтар"));
  EXPECT_FALSE(r.when.isValid());
}

TEST_F(Capture, EstimateTokens) {
  using heap::capture::estimateMinutes;
  EXPECT_EQ(estimateMinutes(u"~30m"), 30);
  EXPECT_EQ(estimateMinutes(u"~45мин"), 45);
  EXPECT_EQ(estimateMinutes(u"~1.5h"), 90);
  EXPECT_EQ(estimateMinutes(u"~1,5ч"), 90);
  EXPECT_EQ(estimateMinutes(u"~2ч"), 120);
  EXPECT_EQ(estimateMinutes(u"~1h30m"), 90);
  EXPECT_EQ(estimateMinutes(u"~soon"), 0);
  EXPECT_EQ(estimateMinutes(u"30m"), 0) << "the tilde is the marker";
}

TEST_F(Capture, AnEstimateIsCutOutAndNotReadAsATime) {
  const Parsed r = p(QStringLiteral("ревью PR ~2ч завтра"));
  EXPECT_EQ(r.estimateMinutes, 120);
  EXPECT_EQ(r.title, QStringLiteral("ревью PR"));
  EXPECT_EQ(r.when.date(), QDate(2026, 5, 21));
  EXPECT_FALSE(r.whenHasTime) << "\"2ч\" is the estimate, not two o'clock";
}

TEST_F(Capture, EmptyAndPlainText) {
  EXPECT_TRUE(p(QString()).title.isEmpty());
  const Parsed r = p(QStringLiteral("просто задача"));
  EXPECT_EQ(r.title, QStringLiteral("просто задача"));
  EXPECT_TRUE(r.spans.isEmpty());
}
