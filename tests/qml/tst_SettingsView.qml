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
