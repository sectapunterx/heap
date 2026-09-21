// SettingsView (qml/SettingsView.qml) defaults.
//
// SettingsView owns a `defaults` blob that _mergeDefaults() lays user-stored
// settings on top of, and _persistNow() writes the *whole* merged result back
// to AppController.appSettingsJson. So a default here is not inert: the first
// time the user changes any setting at all, every default in this blob becomes
// a stored value that Theme then reads. A default that disagrees with Theme's
// own fallback changes the app's behaviour as a side effect of an unrelated
// click, which is what these cases pin.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "SettingsView"
    when: windowShown
    visible: true
    width: 900
    height: 600

    Item { id: host; anchors.fill: parent }

    function make() {
        const sv = createTemporaryQmlObject(
            'import TodoCpp; SettingsView { anchors.fill: parent }', host);
        verify(sv !== null);
        return sv;
    }

    function test_smoke_load() {
        const sv = make();
        verify(sv.defaults !== undefined);
        verify(sv.defaults.calendar !== undefined);
    }

    // showWeekends defaulted to false here while Theme defaulted it to true.
    // Changing the accent colour was enough to persist the blob, and the
    // weekend columns then disappeared from the calendar — a setting the user
    // never touched, changed by a click somewhere else.
    function test_calendar_defaults_agree_with_theme() {
        const sv = make();
        const saved = AppController.appSettingsJson;

        AppController.appSettingsJson = "";   // Theme falls back to its own defaults
        const themeWeekStart    = Theme.weekStart;
        const themeTimeFormat   = Theme.timeFormat;
        const themeSnapMinutes  = Theme.snapMinutes;
        const themeShowWeekends = Theme.showWeekends;
        AppController.appSettingsJson = saved;

        compare(sv.defaults.calendar.showWeekends, themeShowWeekends);
        compare(sv.defaults.calendar.weekStart,    themeWeekStart);
        compare(sv.defaults.calendar.timeFormat,   themeTimeFormat);
        compare(sv.defaults.calendar.snapMinutes,  themeSnapMinutes);
    }

    // _mergeDefaults keeps an explicitly stored value, including a falsy one.
    function test_merge_defaults_keeps_a_stored_false() {
        const sv = make();
        const merged = sv._mergeDefaults({ calendar: { showWeekends: false } });
        compare(merged.calendar.showWeekends, false);
        // unrelated keys still come from the defaults
        compare(merged.calendar.weekStart, sv.defaults.calendar.weekStart);
    }

    // ─── Integrations: connecting by hand ─────────────────────────────
    // The Connect button was hidden on any card that could do a browser
    // sign-in, so an OAuth-capable provider filled in under Advanced — a
    // personal access token, a self-hosted Jira — showed a full set of fields
    // and nothing but "Test connection" to press.

    // Settings are app-wide, so every case that writes them puts back what it
    // found — including one that fails partway through.
    property string savedSettings: ""
    property bool settingsSaved: false

    function cleanup() {
        if (!settingsSaved)
            return;
        AppController.appSettingsJson = savedSettings;
        settingsSaved = false;
    }

    // One provider's card, expanded, with `cfg` as its stored config.
    function _card(sv, provider, cfg) {
        if (!settingsSaved) {
            savedSettings = AppController.appSettingsJson;
            settingsSaved = true;
        }
        const settings = JSON.parse(AppController.appSettingsJson || "{}");
        settings.integrations = settings.integrations || ({});
        settings.integrations[provider] = cfg;
        AppController.appSettingsJson = JSON.stringify(settings);
        sv._loadFromController();
        sv.activeSection = "integrations";
        tryVerify(function () { return findChild(sv, "int-card-" + provider) !== null; },
                  2000, provider + " must have a card on the Integrations page");
        const card = findChild(sv, "int-card-" + provider);
        // A collapsed card makes every child read `visible: false`, whatever
        // the binding under test says.
        card.open = true;
        return card;
    }

    function test_connect_is_offered_for_a_hand_filled_oauth_card() {
        const sv = make();

        // A client ID is what makes a card one-click-capable without a baked
        // credential — the self-hosted path, and the shape every OAuth card
        // has in a release build.
        const card = _card(sv, "jira", { clientId: "cid" });
        compare(card.canOneClick, true);

        const connect = findChild(sv, "int-connect-jira");
        verify(connect !== null);
        compare(connect.visible, false, "the browser button is the default for a one-click card");

        card.advanced = true;
        compare(connect.visible, true, "fields on screen with no way to connect is a dead end");
    }

    // Redmine has no browser flow in any build, so its card is the token-only
    // shape — the one the Connect button never left.
    function test_connect_stays_on_a_card_that_cannot_use_the_browser() {
        const sv = make();

        const card = _card(sv, "redmine", ({}));
        compare(card.canOneClick, false);
        compare(findChild(sv, "int-connect-redmine").visible, true);
    }

    function test_a_connected_card_has_nothing_left_to_connect() {
        const sv = make();

        const card = _card(sv, "jira", { clientId: "cid", connected: true });
        card.advanced = true;
        compare(findChild(sv, "int-connect-jira").visible, false);
    }

    // A stored 0 is a real value. These reads used `|| <default>`, so a
    // A stored 0 is a real value. These reads used `|| <default>`, so a
    // hand-edited zero silently became the default instead.
    function test_merge_defaults_keeps_a_stored_zero() {
        const sv = make();
        const merged = sv._mergeDefaults({
            calendar: { snapMinutes: 0, focusBlockDuration: 0 },
            notifications: { deadlineLeadHours: 0 }
        });
        compare(merged.calendar.snapMinutes, 0);
        compare(merged.calendar.focusBlockDuration, 0);
        compare(merged.notifications.deadlineLeadHours, 0);
    }
}
