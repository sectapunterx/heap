// Settings → Integrations: the "Calendars by link" card (APP-118) and the
// "How integrations work" block above it.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "CalendarSubscriptionsCard"
    when: windowShown
    visible: true
    width: 900
    height: 700

    Item { id: host; anchors.fill: parent }

    property string savedSettings: ""

    function init() {
        tc.savedSettings = AppController.appSettingsJson;
        AppController.appSettingsJson = "";
    }
    function cleanup() {
        AppController.appSettingsJson = tc.savedSettings;
    }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // A link that is not http(s)/webcal is refused on the spot, with the
    // reason under the field, and nothing is added.
    function test_a_bad_link_is_refused() {
        const card = make('import TodoCpp; CalendarSubscriptionsCard { width: 860 }');
        findChild(card, "calsub-link").text = "ftp://example.com/cal.ics";
        verify(!card.add());
        verify(findChild(card, "calsub-error").visible);
        compare(AppController.calendarSubscriptions.length, 0);
    }

    // A calendar in the settings is listed with its refresh interval and how
    // its last fetch went; this one has no link in the keychain, which it says.
    function test_a_subscription_is_listed_with_its_status() {
        AppController.appSettingsJson = JSON.stringify({ calendars: { subscriptions: [
            { id: "qprobe", name: "Work", minutes: 30 } ] } });
        const card = make('import TodoCpp; CalendarSubscriptionsCard { width: 860 }');
        tryVerify(() => findChild(card, "calsub-row-qprobe") !== null, 2000);
        tryVerify(() => String(findChild(card, "calsub-status-qprobe").text).length > 0, 2000);
        verify(findChild(card, "calsub-refresh-qprobe") !== null);
    }

    function test_the_interval_pills_pick_one() {
        const card = make('import TodoCpp; CalendarSubscriptionsCard { width: 860 }');
        compare(card.everyIndex, 1);
        findChild(card, "calsub-every-60").clicked();
        compare(card.everyIndex, 3);
        verify(findChild(card, "calsub-every-60").selected);
        verify(!findChild(card, "calsub-every-15").selected);
    }
}
