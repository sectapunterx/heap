// A mirrored card's sync indicator and conflict dialog (APP-163). Driven with
// hand-made task maps: the C++ side of the states is covered by
// test_sync_state / test_int_audit.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "SyncIndicator"
    when: windowShown
    visible: true
    width: 600
    height: 600

    Item { id: host; anchors.fill: parent }

    // These states are the ones a tracker heap writes to shows; with the
    // switch off (the default since APP-243) an unsent move reads "not sent",
    // which tst_TrackerWrites covers.
    property string savedSettings: ""
    function init() {
        savedSettings = AppController.appSettingsJson;
        AppController.appSettingsJson = "{}";
        AppController.setTrackerWriteEnabled("github", true);
    }
    function cleanup() {
        AppController.appSettingsJson = savedSettings;
    }

    Component {
        id: cardComp
        TaskCard { width: 360 }
    }

    function make(ticketFields, taskFields) {
        const ticket = Object.assign({ provider: "github", key: "#7", url: "https://github.com/a/b/issues/7" },
                                     ticketFields);
        const task = Object.assign({ id: "vision-sync-7", title: "Mine", desc: "", priority: "P2", status: "prog",
                                     labels: [], ticket: ticket }, taskFields || {});
        const o = cardComp.createObject(host, { task: task });
        verify(o !== null);
        return o;
    }

    function test_in_step_shows_nothing() {
        const card = make({ syncState: "synced" });
        verify(!findChild(card, "tc-sync-state").visible, "an indicator on a synced card");
        verify(!findChild(card, "tc-conflict").visible);
        card.destroy();
    }

    function test_each_out_of_step_state_has_its_word() {
        const cases = [["pushing", "taskcard.pushing"], ["queued", "taskcard.queued"],
                       ["error", "taskcard.unsynced"], ["gone", "taskcard.gone"]];
        for (let i = 0; i < cases.length; ++i) {
            const card = make({ syncState: cases[i][0], gone: cases[i][0] === "gone" });
            const chip = findChild(card, "tc-sync-state");
            verify(chip.visible, cases[i][0] + " is not shown");
            compare(findChild(card, "tc-sync-state-text").text, I18n.t(cases[i][1]));
            card.destroy();
        }
    }

    function test_refusal_carries_the_trackers_reason() {
        const card = make({ syncState: "error", unsynced: true, syncError: "HTTP 403 — forbidden" });
        verify(findChild(card, "tc-sync-state").tip.indexOf("HTTP 403 — forbidden") >= 0, "the reason is lost");
        card.destroy();
    }

    function test_older_task_maps_still_show_the_state() {
        // The archive builds its own map without syncState.
        const card = make({ unsynced: true, queued: true });
        verify(findChild(card, "tc-sync-state").visible);
        compare(findChild(card, "tc-sync-state-text").text, I18n.t("taskcard.queued"));
        card.destroy();
    }

    function test_conflict_opens_a_side_by_side_choice() {
        const card = make({ syncState: "conflict", conflict: true, conflicts: ["status"],
                            remoteColumn: "done", remoteStatus: "closed" });
        verify(findChild(card, "tc-conflict").visible);
        card.openConflictDialog();
        const dlg = card.conflictDialog;
        verify(dlg !== null, "no dialog");
        tryCompare(dlg, "opened", true);
        compare(dlg.rows.length, 1);
        compare(dlg.rows[0].field, "status");
        verify(dlg.rows[0].theirs.indexOf("closed") >= 0, "the tracker's side is not shown");
        verify(findChild(dlg.contentItem, "sync-conflict-keep-status") !== null);
        verify(findChild(dlg.contentItem, "sync-conflict-take-status") !== null);
        dlg.close();
        tryCompare(dlg, "visible", false);
        card.destroy();
    }

    function test_strings_exist_in_both_languages() {
        const keys = ["taskcard.pushing", "taskcard.pushing.tip", "taskcard.queued", "taskcard.syncError",
                      "sync.conflict.title", "sync.conflict.body", "sync.conflict.here", "sync.conflict.tracker",
                      "sync.conflict.keepAndSend", "sync.conflict.takeTracker", "sync.conflict.open",
                      "ticket.conflict.status"];
        for (let i = 0; i < keys.length; ++i) {
            verify(I18n.dict.en[keys[i]] !== undefined, keys[i] + " missing in en");
            verify(I18n.dict.ru[keys[i]] !== undefined, keys[i] + " missing in ru");
        }
    }
}
