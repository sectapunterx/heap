#include <gtest/gtest.h>

#include "notify/NotificationCenter.h"

#include <QObject>
#include <QSignalSpy>

using heap::notify::Notification;
using heap::notify::NotificationAction;
using heap::notify::NotificationCenter;
using heap::notify::parseRoutingId;
using heap::notify::routingId;

// ─── routingId / parseRoutingId ────────────────────────────────────

TEST(Routing, MakeIdWithKind) {
    EXPECT_EQ(routingId(QStringLiteral("deadline"), QStringLiteral("LTE-2398")),
              QString("deadline:LTE-2398"));
}

TEST(Routing, EmptyKindFallsBackToTask) {
    EXPECT_EQ(routingId(QString(), QStringLiteral("LTE-2398")),
              QString("task:LTE-2398"));
}

TEST(Routing, ParseRoundTrip) {
    const auto [kind, task] = parseRoutingId(QStringLiteral("standup:LTE-1"));
    EXPECT_EQ(kind, QString("standup"));
    EXPECT_EQ(task, QString("LTE-1"));
}

TEST(Routing, ParseDefaultKind) {
    const auto [kind, task] = parseRoutingId(QStringLiteral("task:RAN-99"));
    EXPECT_EQ(kind, QString("task"));
    EXPECT_EQ(task, QString("RAN-99"));
}

TEST(Routing, ParseRejectsNoColon) {
    const auto [k, t] = parseRoutingId(QStringLiteral("no-colon-here"));
    EXPECT_TRUE(k.isEmpty());
    EXPECT_TRUE(t.isEmpty());
}

TEST(Routing, ParseRejectsLeadingColon) {
    // ":foo" — empty kind is malformed.
    const auto [k, t] = parseRoutingId(QStringLiteral(":foo"));
    EXPECT_TRUE(k.isEmpty());
    EXPECT_TRUE(t.isEmpty());
}

TEST(Routing, ParseRejectsTrailingColon) {
    const auto [k, t] = parseRoutingId(QStringLiteral("deadline:"));
    EXPECT_TRUE(k.isEmpty());
    EXPECT_TRUE(t.isEmpty());
}

TEST(Routing, RoundTripPreservesData) {
    const auto id = routingId(QStringLiteral("git"), QStringLiteral("HEAP-7"));
    const auto [k, t] = parseRoutingId(id);
    EXPECT_EQ(k, QString("git"));
    EXPECT_EQ(t, QString("HEAP-7"));
}

// ─── Notification / NotificationAction structs ─────────────────────

TEST(Notification, DefaultDurationZero) {
    Notification n;
    EXPECT_EQ(n.durationSec, 0);
    EXPECT_TRUE(n.actions.isEmpty());
    EXPECT_TRUE(n.title.isEmpty());
    EXPECT_TRUE(n.body.isEmpty());
}

TEST(NotificationAction, IdLabelStored) {
    NotificationAction a{ QStringLiteral("snooze1h"), QStringLiteral("Snooze 1h") };
    EXPECT_EQ(a.id, QString("snooze1h"));
    EXPECT_EQ(a.label, QString("Snooze 1h"));
}

TEST(Notification, ActionsCarry) {
    Notification n;
    n.actions = {
        { QStringLiteral("snooze1h"), QStringLiteral("Snooze 1h") },
        { QStringLiteral("done"),     QStringLiteral("Mark done") },
        { QStringLiteral("open"),     QStringLiteral("Open") }
    };
    ASSERT_EQ(n.actions.size(), 3);
    EXPECT_EQ(n.actions.at(2).id, QString("open"));
}

// ─── NotificationCenter via in-test mock ───────────────────────────
// Exercises the abstract API + the signal contract that AppController
// relies on. No real OS backend involved.

class MockCenter : public NotificationCenter {
    Q_OBJECT
public:
    explicit MockCenter(QObject *parent = nullptr)
        : NotificationCenter(parent) {}

    void post(const Notification &n) override { lastPosted = n; ++postCount; }
    void dismiss(const QString &id) override { dismissedIds.append(id); }
    bool supportsActions() const override { return true; }

    int          postCount = 0;
    Notification lastPosted;
    QStringList  dismissedIds;

    // Test-only ways to fire the protected signals.
    void simulateAction(const QString &nid, const QString &aid) {
        emit actionInvoked(nid, aid);
    }
    void simulateActivated(const QString &nid) { emit activated(nid); }
};

TEST(NotificationCenter, PostRecordsNotification) {
    MockCenter c;
    Notification n;
    n.id    = QStringLiteral("deadline:LTE-1");
    n.title = QStringLiteral("hello");
    c.post(n);
    EXPECT_EQ(c.postCount, 1);
    EXPECT_EQ(c.lastPosted.id,    QString("deadline:LTE-1"));
    EXPECT_EQ(c.lastPosted.title, QString("hello"));
}

TEST(NotificationCenter, DismissRecordsId) {
    MockCenter c;
    c.dismiss(QStringLiteral("foo:bar"));
    ASSERT_EQ(c.dismissedIds.size(), 1);
    EXPECT_EQ(c.dismissedIds.at(0), QString("foo:bar"));
}

TEST(NotificationCenter, ActionInvokedSignal) {
    MockCenter c;
    QSignalSpy spy(&c, &NotificationCenter::actionInvoked);
    c.simulateAction(QStringLiteral("deadline:LTE-1"), QStringLiteral("snooze1h"));
    ASSERT_EQ(spy.count(), 1);
    const auto args = spy.takeFirst();
    EXPECT_EQ(args.at(0).toString(), QString("deadline:LTE-1"));
    EXPECT_EQ(args.at(1).toString(), QString("snooze1h"));
}

TEST(NotificationCenter, ActivatedSignal) {
    MockCenter c;
    QSignalSpy spy(&c, &NotificationCenter::activated);
    c.simulateActivated(QStringLiteral("git:HEAP-9"));
    ASSERT_EQ(spy.count(), 1);
    EXPECT_EQ(spy.takeFirst().at(0).toString(), QString("git:HEAP-9"));
}

#include "test_notification.moc"
