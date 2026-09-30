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

    // A mapped status must show its column, not "Auto" (audit B1): the combo
    // read indexOfValue() before it had a model and never looked again.
    function test_status_map_combo_shows_the_chosen_column() {
        const sv = make();
        const card = _card(sv, "jira", {
            clientId: "cid", connected: true,
            seenStatuses: ["In Progress", "To Do"],
            statusMap: { "In Progress": "blocked" }
        });
        tryVerify(function () { return findChild(sv, "status-map-combo") !== null; }, 2000);
        const combo = findChild(sv, "status-map-combo");
        tryCompare(combo, "currentValue", "blocked");
        verify(combo.currentIndex > 0);
    }

    // The mapping folds away: closed by default, the header says what is
    // behind it, and a click opens it.
    function test_status_map_folds_and_unfolds() {
        const sv = make();
        const card = _card(sv, "jira", {
            clientId: "cid", connected: true,
            seenStatuses: ["In Progress", "To Do", "Done"],
            statusMap: { "In Progress": "blocked" }
        });
        tryVerify(function () { return findChild(card, "status-map-toggle-area") !== null; }, 2000);
        // The card sits below the fold of the settings page, out of reach of
        // a synthetic click; the header's own handler is what a click runs.
        const toggle = findChild(card, "status-map-toggle-area");
        verify(!card.mapOpen, "the status mapping must start folded");
        const combo = findChild(card, "status-map-combo");
        verify(!combo.parent.visible, "a folded mapping still shows its rows");

        toggle.activated();
        tryVerify(function () { return card.mapOpen; }, 1000, "a click did not unfold the mapping");
        verify(combo.parent.visible);

        toggle.activated();
        tryVerify(function () { return !card.mapOpen; }, 1000, "a second click did not fold it again");
    }

    // ─── Integrations: busy buttons and the last error (DES-5) ─────────
    // "Sync now" and "Test connection" stayed clickable while the request ran,
    // and a failure lived only in a toast that was gone in three seconds.

    SignalSpy { id: activatedSpy; signalName: "activated" }

    function test_a_running_sync_is_busy_and_ignores_a_second_press() {
        const sv = make();
        IntegrationActivity.clear("redmine");
        _card(sv, "redmine", { connected: true });
        const sync = findChild(sv, "int-sync-redmine");
        verify(sync !== null);
        compare(sync.available, true);

        IntegrationActivity.start("redmine", "sync");
        compare(sync.busy, true);
        compare(sync.available, false, "a busy button still took presses");
        compare(sync.shownText, I18n.t("settings.integrations.syncing"));
        compare(sync.Accessible.name, I18n.t("settings.integrations.syncing"));

        activatedSpy.clear();
        activatedSpy.target = sync;
        sync.forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(activatedSpy.count, 0, "Return ran a sync that is already running");
        verify(sync.activeFocus, "going busy took the keyboard away");

        IntegrationActivity.finish("redmine", "sync", true, "");
        compare(sync.busy, false);
        compare(sync.available, true);
    }

    function test_a_failure_stays_on_the_card_until_the_next_success() {
        const sv = make();
        IntegrationActivity.clear("redmine");
        _card(sv, "redmine", { connected: true });
        const err = findChild(sv, "int-last-error-redmine");
        const synced = findChild(sv, "int-last-sync-redmine");
        compare(err.visible, false);

        IntegrationActivity.start("redmine", "test");
        IntegrationActivity.finish("redmine", "test", false, "Redmine: 401 bad token");
        compare(err.visible, true, "the error went with the toast");
        verify(err.text.indexOf("401 bad token") >= 0, err.text);
        compare(findChild(sv, "int-test-redmine").busy, false);

        IntegrationActivity.finish("redmine", "sync", true, "");
        compare(err.visible, false, "a sync that worked left the old error up");
        compare(synced.visible, true, "no last-sync time after a sync");
    }

    // The real round trip: a card marked connected with no token has no
    // tracker behind it, so AppController answers the sync at once — as a
    // failure the card keeps, not only a toast.
    function test_sync_now_with_no_tracker_shows_why() {
        const sv = make();
        IntegrationActivity.clear("redmine");
        _card(sv, "redmine", { connected: true });
        const sync = findChild(sv, "int-sync-redmine");
        sync.forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(sync.busy, false, "the answer came back and the button stayed busy");
        const err = findChild(sv, "int-last-error-redmine");
        compare(err.visible, true);
        verify(err.text.length > 0);
    }

    // Settings is rebuilt as the user moves around; an answer that came in
    // meanwhile is still on the card when they come back.
    function test_the_last_error_outlives_the_settings_view() {
        IntegrationActivity.clear("redmine");
        IntegrationActivity.finish("redmine", "sync", false, "Redmine sync failed: 404");
        const sv = make();
        _card(sv, "redmine", { connected: true });
        const err = findChild(sv, "int-last-error-redmine");
        compare(err.visible, true);
        verify(err.text.indexOf("404") >= 0, err.text);
        IntegrationActivity.clear("redmine");
        compare(err.visible, false);
    }

    function test_a_busy_limit_frees_a_button_nobody_answered() {
        const sv = make();
        IntegrationActivity.clear("redmine");
        _card(sv, "redmine", { connected: true });
        IntegrationActivity.start("redmine", "sync");
        IntegrationActivity.expire(Date.now() + 10 * 60 * 1000);
        compare(findChild(sv, "int-sync-redmine").busy, false);
        compare(findChild(sv, "int-last-error-redmine").visible, false,
                "a timeout is not an answer and must not invent an error");
    }

    // ─── Settings actions on the keyboard (DES-8) ──────────────────────
    // Export, Import, Restore, Wipe, Report, Logs, Check updates were
    // Rectangle + MouseArea: no Tab stop, no name, no disabled state.

    function test_data_actions_are_on_the_tab_path_and_named() {
        const sv = make();
        sv.activeSection = "data";
        tryVerify(function () { return findChild(sv, "settings-export-json") !== null; }, 2000);
        const exp = findChild(sv, "settings-export-json");
        const imp = findChild(sv, "settings-import-json");
        verify(exp.activeFocusOnTab);
        compare(exp.Accessible.role, Accessible.Button);
        compare(exp.Accessible.name, I18n.t("settings.data.exportJson"));
        exp.forceActiveFocus();
        keyClick(Qt.Key_Tab);
        verify(imp.activeFocus, "Tab from Export did not reach Import");
    }

    // Design audit DES-16: "Delete everything" asks in a dialog that names
    // the profiles that go, with focus on Cancel; nothing is wiped until the
    // red button in it is pressed.
    function test_wipe_asks_in_a_dialog_with_focus_on_cancel() {
        const sv = make();
        sv.activeSection = "data";
        tryVerify(function () { return findChild(sv, "settings-wipe") !== null; }, 2000);
        const wipe = findChild(sv, "settings-wipe");
        const dialog = findChild(sv, "settings-wipe-dialog");
        verify(dialog !== null);
        const before = AppController.profiles.length;
        wipe.forceActiveFocus();
        keyClick(Qt.Key_Space);
        tryVerify(function () { return dialog.opened; }, 1000, "Space did not open the wipe dialog");
        const body = findChild(dialog.contentItem, "settings-wipe-dialog-body");
        const firstName = AppController.profiles[0].name;
        verify(body.text.indexOf(firstName) >= 0, "the dialog does not name the profiles: " + body.text);
        const cancel = findChild(dialog.contentItem, "settings-wipe-cancel");
        tryVerify(function () { return cancel.activeFocus; }, 1000, "focus is not on Cancel");
        keyClick(Qt.Key_Escape);
        tryVerify(function () { return !dialog.opened; }, 1000);
        compare(AppController.profiles.length, before, "the profiles were touched");
    }

    function test_about_actions_are_named_buttons() {
        const sv = make();
        sv.activeSection = "about";
        tryVerify(function () { return findChild(sv, "settings-open-logs") !== null; }, 2000);
        const names = {
            "settings-report-issue": "settings.about.reportIssue",
            "settings-open-logs": "settings.about.openLogs",
            "settings-check-updates": "settings.about.checkUpdates"
        };
        for (const id in names) {
            const b = findChild(sv, id);
            verify(b !== null, id);
            verify(b.activeFocusOnTab, id + " is not on the Tab path");
            compare(b.Accessible.role, Accessible.Button, id);
            compare(b.Accessible.name, I18n.t(names[id]), id);
        }
    }

    // The button itself: Return, Enter and Space run it, a disabled one
    // neither runs nor looks live. (The Settings instances open a browser,
    // a folder or the network, so their keys are pinned here instead.)
    function test_action_button_keys_and_disabled_state() {
        const b = createTemporaryQmlObject('import TodoCpp; ActionButton { text: "Go" }', host);
        activatedSpy.clear();
        activatedSpy.target = b;
        b.forceActiveFocus();
        verify(b.activeFocus);
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Enter);
        keyClick(Qt.Key_Space);
        compare(activatedSpy.count, 3);
        compare(b.opacity, 1);

        b.enabled = false;
        compare(b.available, false);
        compare(b.opacity, 0.45, "a disabled button looked live");
        b.press();
        compare(activatedSpy.count, 3, "a disabled button still ran");
    }
}
