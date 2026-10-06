// Native notifications with buttons (APP-155): the heap://notify URI a click
// comes back with, the Windows toast document, and the snooze arithmetic.
#include "notify/NotificationCenter.h"
#include "notify/NotifyPayload.h"

#include <QObject>
#include <QSignalSpy>

#include <gtest/gtest.h>

using namespace heap::notify;

namespace {

// The base class's own parsing, through a backend that shows nothing.
class SilentBackend : public NotificationCenter {
 public:
  using NotificationCenter::NotificationCenter;

  void post(const Notification& /*n*/) override {
  }

  void dismiss(const QString& /*id*/) override {
  }

  bool supportsActions() const override {
    return true;
  }
};

Notification reminder() {
  Notification n;
  n.id = QStringLiteral("deadline:TASK-7");
  n.title = QStringLiteral("Due in 1 h");
  n.body = QStringLiteral("Fix <login> & \"logout\" (P1)");
  n.actions = {{QString::fromLatin1(kSnoozeShort), QStringLiteral("Snooze 10 min")},
               {QString::fromLatin1(kSnoozeLong), QStringLiteral("Snooze 1 h")},
               {QString::fromLatin1(kOpen), QStringLiteral("Open")}};
  return n;
}

}  // namespace

// ── heap://notify ──

TEST(NotifyUri, RoundTrip) {
  const QString uri = notifyUri(QStringLiteral("deadline:TASK-7"), QStringLiteral("snoozeShort"));
  EXPECT_EQ(uri, QStringLiteral("heap://notify?id=deadline%3ATASK-7&action=snoozeShort"));
  const NotifyUri parsed = parseNotifyUri(uri);
  ASSERT_TRUE(parsed.ok);
  EXPECT_EQ(parsed.notificationId, QStringLiteral("deadline:TASK-7"));
  EXPECT_EQ(parsed.actionId, QStringLiteral("snoozeShort"));
  EXPECT_TRUE(parsed.dataDir.isEmpty());
}

// Ids and folders with the query's own delimiters, spaces and non-ASCII.
TEST(NotifyUri, AwkwardCharactersSurvive) {
  const QString id = QStringLiteral("meeting:ev&1=2 #x+y");
  const QString dir = QStringLiteral("C:\\Users\\Фин\\heap test&co");
  const NotifyUri parsed = parseNotifyUri(notifyUri(id, QStringLiteral("open"), dir));
  ASSERT_TRUE(parsed.ok);
  EXPECT_EQ(parsed.notificationId, id);
  EXPECT_EQ(parsed.actionId, QStringLiteral("open"));
  EXPECT_EQ(parsed.dataDir, dir);
}

TEST(NotifyUri, NoActionMeansTheNotificationItself) {
  const NotifyUri parsed = parseNotifyUri(QStringLiteral("heap://notify?id=task%3AA-1"));
  ASSERT_TRUE(parsed.ok);
  EXPECT_EQ(parsed.actionId, QString::fromLatin1(kDefaultAction));
  EXPECT_EQ(parseNotifyUri(notifyUri(QStringLiteral("task:A-1"), QString())).actionId, QString::fromLatin1(kDefaultAction));
}

// What the shell may do to it: a slash before the query, an upper-case scheme.
TEST(NotifyUri, ToleratesShellSpelling) {
  EXPECT_TRUE(parseNotifyUri(QStringLiteral("heap://notify/?id=a%3Ab&action=open")).ok);
  EXPECT_TRUE(parseNotifyUri(QStringLiteral("HEAP://notify?id=a%3Ab")).ok);
  EXPECT_TRUE(isNotifyUri(QStringLiteral("HEAP://notify?id=a")));
}

TEST(NotifyUri, RejectsAnythingElse) {
  EXPECT_FALSE(parseNotifyUri(QString()).ok);
  EXPECT_FALSE(parseNotifyUri(QStringLiteral("heap://notify?action=open")).ok);
  EXPECT_FALSE(parseNotifyUri(QStringLiteral("heap://other?id=a")).ok);
  EXPECT_FALSE(parseNotifyUri(QStringLiteral("https://notify?id=a")).ok);
  EXPECT_FALSE(parseNotifyUri(QStringLiteral("heap://notify/deep/path?id=a")).ok);
  EXPECT_FALSE(isNotifyUri(QStringLiteral("--view")));
  EXPECT_FALSE(isNotifyUri(QStringLiteral("board")));
}

TEST(NotifyUri, BaseClassEmitsTheRightSignal) {
  SilentBackend backend(nullptr);
  const QSignalSpy actions(&backend, &NotificationCenter::actionInvoked);
  const QSignalSpy activations(&backend, &NotificationCenter::activated);

  EXPECT_TRUE(backend.handleActivationUri(notifyUri(QStringLiteral("deadline:T-1"), QStringLiteral("snoozeLong"))));
  ASSERT_EQ(actions.count(), 1);
  EXPECT_EQ(actions.at(0).at(0).toString(), QStringLiteral("deadline:T-1"));
  EXPECT_EQ(actions.at(0).at(1).toString(), QStringLiteral("snoozeLong"));

  EXPECT_TRUE(backend.handleActivationUri(notifyUri(QStringLiteral("deadline:T-1"), QString())));
  ASSERT_EQ(activations.count(), 1);
  EXPECT_EQ(activations.at(0).at(0).toString(), QStringLiteral("deadline:T-1"));

  EXPECT_FALSE(backend.handleActivationUri(QStringLiteral("heap://notify")));
  EXPECT_EQ(actions.count() + activations.count(), 2);
}

// ── Toast XML ──

TEST(ToastXml, EscapesTextAndCarriesOneProtocolButtonPerAction) {
  const QString xml = toastXml(reminder(), QString());
  EXPECT_TRUE(
      xml.startsWith(QStringLiteral("<toast launch=\"heap://notify?id=deadline%3ATASK-7&amp;action=default\" "
                                    "activationType=\"protocol\">")));
  EXPECT_TRUE(xml.contains(QStringLiteral("<text>Due in 1 h</text>")));
  EXPECT_TRUE(xml.contains(QStringLiteral("<text>Fix &lt;login&gt; &amp; &quot;logout&quot; (P1)</text>")));
  EXPECT_TRUE(
      xml.contains(QStringLiteral("<action content=\"Snooze 10 min\" "
                                  "arguments=\"heap://notify?id=deadline%3ATASK-7&amp;action=snoozeShort\" "
                                  "activationType=\"protocol\"/>")));
  EXPECT_EQ(xml.count(QStringLiteral("<action ")), 3);
  EXPECT_FALSE(xml.contains(QStringLiteral("<image")));
  EXPECT_TRUE(xml.endsWith(QStringLiteral("</actions></toast>")));
}

TEST(ToastXml, NoActionsNoActionsElement) {
  Notification n = reminder();
  n.actions.clear();
  EXPECT_FALSE(toastXml(n, QString()).contains(QStringLiteral("<actions>")));
}

TEST(ToastXml, ThrowawayProfileAndLogo) {
  const QString xml = toastXml(reminder(), QStringLiteral("C:/tmp/heap x"), QStringLiteral("C:/tmp/heap x/toast-icon.png"));
  EXPECT_TRUE(xml.contains(QStringLiteral("&amp;dir=C%3A%2Ftmp%2Fheap%20x")));
  EXPECT_TRUE(xml.contains(QStringLiteral("<image placement=\"appLogoOverride\" src=\"file:///C:/tmp/heap%20x/toast-icon.png\"/>")));
}

// Windows refuses a toast with more than five buttons, so extras are dropped.
TEST(ToastXml, AtMostFiveButtons) {
  Notification n = reminder();
  for(int i = 0; i < 4; ++i) {
    n.actions.append({QStringLiteral("x%1").arg(i), QStringLiteral("X")});
  }
  EXPECT_EQ(toastXml(n, QString()).count(QStringLiteral("<action ")), 5);
}

// ── Snooze ──

TEST(Snooze, MinutesPerButton) {
  EXPECT_EQ(snoozeMinutesFor(QString::fromLatin1(kSnoozeShort), 10, 60), 10);
  EXPECT_EQ(snoozeMinutesFor(QString::fromLatin1(kSnoozeLong), 10, 45), 45);
  EXPECT_EQ(snoozeMinutesFor(QString::fromLatin1(kLegacySnooze1h), 10, 45), 60);
  EXPECT_EQ(snoozeMinutesFor(QString::fromLatin1(kOpen), 10, 60), 0);
  // A hand-edited setting cannot snooze for nothing or for days.
  EXPECT_EQ(snoozeMinutesFor(QString::fromLatin1(kSnoozeShort), 0, 60), kMinSnoozeMin);
  EXPECT_EQ(snoozeMinutesFor(QString::fromLatin1(kSnoozeLong), 10, 100000), kMaxSnoozeMin);
}

TEST(Snooze, ComesBackAfterTheDuration) {
  const QDateTime now(QDate(2026, 10, 6), QTime(23, 55));
  EXPECT_EQ(snoozeUntil(now, 10), QDateTime(QDate(2026, 10, 7), QTime(0, 5)));
  EXPECT_EQ(snoozeUntil(now, 60), QDateTime(QDate(2026, 10, 7), QTime(0, 55)));
  EXPECT_EQ(snoozeUntil(now, -5), now.addSecs(60));
}

TEST(Snooze, Labels) {
  EXPECT_EQ(snoozeLabel(10, false), QStringLiteral("Snooze 10 min"));
  EXPECT_EQ(snoozeLabel(60, false), QStringLiteral("Snooze 1 h"));
  EXPECT_EQ(snoozeLabel(120, true), QStringLiteral("Отложить на 2 ч"));
  EXPECT_EQ(snoozeLabel(90, true), QStringLiteral("Отложить на 90 мин"));
}

TEST(Snooze, SameReminderSnoozedTwiceKeepsTheLaterOne) {
  const QDateTime t0(QDate(2026, 10, 6), QTime(10, 0));
  QVector<SnoozedReminder> pending;
  upsertSnooze(pending, {QStringLiteral("deadline:A"), QStringLiteral("t"), QStringLiteral("b"), QStringLiteral("deadline"), t0});
  upsertSnooze(pending,
               {QStringLiteral("deadline:A"), QStringLiteral("t"), QStringLiteral("b"), QStringLiteral("deadline"), t0.addSecs(3600)});
  ASSERT_EQ(pending.size(), 1);
  EXPECT_EQ(pending.at(0).fireAt, t0.addSecs(3600));
}

TEST(Snooze, TakeDueLeavesTheRest) {
  const QDateTime t0(QDate(2026, 10, 6), QTime(10, 0));
  QVector<SnoozedReminder> pending;
  upsertSnooze(pending, {QStringLiteral("b"), {}, {}, {}, t0.addSecs(120)});
  upsertSnooze(pending, {QStringLiteral("a"), {}, {}, {}, t0.addSecs(60)});
  upsertSnooze(pending, {QStringLiteral("c"), {}, {}, {}, t0.addSecs(600)});

  EXPECT_TRUE(takeDueSnoozes(pending, t0).isEmpty());
  const QVector<SnoozedReminder> due = takeDueSnoozes(pending, t0.addSecs(120));
  ASSERT_EQ(due.size(), 2);
  EXPECT_EQ(due.at(0).id, QStringLiteral("a"));
  EXPECT_EQ(due.at(1).id, QStringLiteral("b"));
  ASSERT_EQ(pending.size(), 1);
  EXPECT_EQ(pending.at(0).id, QStringLiteral("c"));
}
