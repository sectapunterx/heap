// The time machine dialog (APP-162, qml/TimeMachineDialog.qml): it opens,
// Esc closes it, the retention pills write settings.data, and a preview lists
// what was deleted since. Listing, comparing and restoring are AppController's
// and are tested in C++ (tests/test_time_machine.cpp).
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TimeMachineDialog"
    when: windowShown
    visible: true
    width: 1000
    height: 760

    Item { id: host; anchors.fill: parent }

    property string savedSettings: ""

    function init() {
        tc.savedSettings = AppController.appSettingsJson;
        AppController.appSettingsJson = "";
    }
    function cleanup() {
        AppController.appSettingsJson = tc.savedSettings;
    }

    function make() {
        const d = createTemporaryQmlObject('import TodoCpp; TimeMachineDialog {}', host);
        verify(d !== null);
        return d;
    }

    function test_opens_and_esc_closes() {
        const d = make();
        d.showNow();
        tryCompare(d, "opened", true);
        keyClick(Qt.Key_Escape);
        tryCompare(d, "opened", false);
    }

    function test_day_labels() {
        const d = make();
        const p2 = (n) => (n < 10 ? "0" : "") + n;
        const now = new Date();
        const iso = now.getFullYear() + "-" + p2(now.getMonth() + 1) + "-" + p2(now.getDate());
        compare(d.dayLabel(iso), I18n.t("tm.today"));
        const y = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
        compare(d.dayLabel(y.getFullYear() + "-" + p2(y.getMonth() + 1) + "-" + p2(y.getDate())), I18n.t("tm.yesterday"));
    }

    function test_retention_pills_write_settings() {
        const d = make();
        d.showNow();
        tryCompare(d, "opened", true);
        compare(d.keepDays, 30);
        const pill = findChild(d.contentItem, "time-machine-days-90");
        verify(pill !== null);
        mouseClick(pill);
        compare(JSON.parse(AppController.appSettingsJson).data.historyDays, 90);
        compare(d.keepDays, 90);
        const cap = findChild(d.contentItem, "time-machine-cap-500");
        mouseClick(cap);
        compare(JSON.parse(AppController.appSettingsJson).data.historyMaxMb, 500);
        d.close();
    }

    function test_preview_lists_what_was_deleted() {
        const d = make();
        d.open();
        tryCompare(d, "opened", true);
        d.snapshots = [{ name: "state-20261005-1400.json.z", day: "2026-10-05", time: "14:00", tag: "",
                         tasks: 3, notes: 1, docs: 0, profiles: 1, sizeKb: 4 }];
        wait(300);  // the debounced preview of the fake name has come and gone
        d.preview = { ok: true, totals: { tasksAdded: 0, tasksRemoved: 1, tasksChanged: 0 },
                      profiles: [{ id: "work", name: "Work", color: "", tasks: 3, notes: 1, docs: 0, existsNow: true }],
                      missing: [{ kind: "task", id: "APP-9", title: "Gone", profileId: "work", profileName: "Work",
                                  profileExists: true }],
                      changed: [] };
        tryVerify(() => findChild(d.contentItem, "time-machine-missing-APP-9") !== null);
        verify(findChild(d.contentItem, "time-machine-profile-copy-work") !== null);
        verify(findChild(d.contentItem, "time-machine-snap-0") !== null);
        d.close();
    }
}
