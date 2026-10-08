// The Monday recap (WEAK PECAP, qml/WeeklyRecapDialog.qml): when it opens by
// itself, that it opens once a week, and what it lists. The grouping itself is
// AppController::weeklyRecapFor's and is tested in C++.
//
// APP-211: a week counts as seen only once the dialog was closed, and it
// opens by itself only where it can be seen. The rule is a pure function
// given `now`, so the scenarios below run without a clock.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "WeeklyRecapDialog"
    when: windowShown
    visible: true
    width: 800
    height: 700

    Item { id: host; anchors.fill: parent }

    property string savedSettings: ""

    readonly property var sample: ({
        weekStart: "2026-09-28", weekEnd: "2026-10-05",
        groups: [
            { from: "backlog", fromName: "Backlog", fromColor: "#8a8e98",
              to: "prog", toName: "In Progress", toColor: "#5aa9e6",
              tasks: [ { id: "APP-1", title: "one", priority: "P2" },
                       { id: "APP-2", title: "two", priority: "P1" } ] },
            { from: "prog", fromName: "In Progress", fromColor: "#5aa9e6",
              to: "done", toName: "Done", toColor: "#6ec18a",
              tasks: [ { id: "APP-3", title: "three", priority: "P2" } ] }
        ]
    })

    function init() {
        tc.savedSettings = AppController.appSettingsJson;
        AppController.appSettingsJson = "";
    }
    function cleanup() {
        AppController.appSettingsJson = tc.savedSettings;
    }

    function make() {
        const d = createTemporaryQmlObject('import TodoCpp; WeeklyRecapDialog {}', host);
        verify(d !== null);
        return d;
    }

    function test_week_key_is_the_monday() {
        const d = make();
        compare(d.weekKey(new Date(2026, 9, 5)), "2026-10-05");   // Monday
        compare(d.weekKey(new Date(2026, 9, 11)), "2026-10-05");  // Sunday
        compare(d.weekKey(new Date(2026, 9, 12)), "2026-10-12");
    }

    function test_due_once_a_week_and_only_with_moves() {
        const d = make();
        const monday = new Date(2026, 9, 5);
        verify(d.isDue(monday, tc.sample));
        verify(!d.isDue(monday, { groups: [] }), "an empty week opened the recap");

        d._markSeen(monday);
        verify(!d.isDue(new Date(2026, 9, 7), tc.sample), "shown twice in one week");
        verify(d.isDue(new Date(2026, 9, 12), tc.sample), "not shown the next week");
    }

    // The decision, for every way the window can be when the week turns.
    function test_shows_only_when_it_can_be_seen_data() {
        return [
            { tag: "on screen, in front, nothing over it", visible: true, active: true, overlay: false, content: true, want: true },
            { tag: "in the tray or minimised", visible: false, active: false, overlay: false, content: true, want: false },
            { tag: "behind another app", visible: true, active: false, overlay: false, content: true, want: false },
            { tag: "under the task editor", visible: true, active: true, overlay: true, content: true, want: false },
            { tag: "nothing moved last week", visible: true, active: true, overlay: false, content: false, want: false }
        ];
    }
    function test_shows_only_when_it_can_be_seen(row) {
        const d = make();
        compare(d.shouldShowRecap(new Date(2026, 9, 5, 0, 1), "2026-09-28", row.visible, row.active, row.overlay, row.content),
                row.want);
    }

    function test_a_seen_week_is_not_shown_again() {
        const d = make();
        // Seen on Monday: not again that week, wherever the window is...
        verify(!d.shouldShowRecap(new Date(2026, 9, 7, 9, 0), "2026-10-05", true, true, false, true));
        verify(!d.isUnseen(new Date(2026, 9, 11, 23, 59), "2026-10-05", true));
        // ...and the next week is new.
        verify(d.shouldShowRecap(new Date(2026, 9, 12, 0, 0), "2026-10-05", true, true, false, true));
    }

    // (a) open over Sunday → Monday midnight with the window in the tray:
    // nothing is marked; the window coming back shows it; closing marks it.
    function test_week_turns_in_the_tray() {
        const d = make();
        const monday = new Date(2026, 9, 5, 0, 0, 30);
        verify(!d.shouldShowRecap(monday, d.seenWeek, false, false, false, true));
        compare(d.seenWeek, "", "the week was marked seen with the window hidden");
        // Restored from the tray an hour later.
        verify(d.shouldShowRecap(new Date(2026, 9, 5, 1, 0), d.seenWeek, true, true, false, true));
        d.recap = tc.sample;
        d.open();
        tryVerify(() => d.opened);
        compare(d.seenWeek, "", "opening alone marked the week seen");
        d.close();
        tryVerify(() => !d.visible);
        compare(d.seenWeek, "2026-10-05");
        verify(!d.shouldShowRecap(new Date(2026, 9, 5, 1, 1), d.seenWeek, true, true, false, true));
    }

    // (b) the task editor is open when the week turns: shown once it closes.
    function test_week_turns_under_an_overlay() {
        const d = make();
        const monday = new Date(2026, 9, 5, 0, 0);
        verify(!d.shouldShowRecap(monday, d.seenWeek, true, true, true, true));
        verify(d.shouldShowRecap(new Date(2026, 9, 5, 0, 5), d.seenWeek, true, true, false, true));
    }

    // (c) asleep from Friday to Tuesday: the resume is the first chance.
    function test_resume_after_a_long_sleep() {
        const d = make();
        AppController.appSettingsJson = JSON.stringify({ notifications: { recapSeenWeek: "2026-09-28" } });
        compare(d.seenWeek, "2026-09-28");
        verify(d.shouldShowRecap(new Date(2026, 9, 6, 8, 30), d.seenWeek, true, true, false, true));
    }

    // (d) a restart after the recap was seen: the setting survives, so the
    // recap does not come back.
    function test_restart_after_seeing_it() {
        AppController.appSettingsJson = JSON.stringify({ notifications: { recapSeenWeek: "2026-10-05" } });
        const d = make();
        verify(!d.shouldShowRecap(new Date(2026, 9, 6, 9, 0), d.seenWeek, true, true, false, true));
    }

    // The live entry point stands down while the window cannot be seen,
    // and marks nothing.
    function test_show_if_due_waits_for_the_window() {
        const d = make();
        verify(!d.showIfDue(false, false, false));
        verify(!d.showIfDue(true, false, false));
        verify(!d.showIfDue(true, true, true));
        verify(!d.opened);
        compare(d.seenWeek, "");
    }

    // The button's way in: any week, empty or not, and closing it marks the
    // week seen, which takes the dot away.
    function test_show_now_opens_an_empty_week_and_closing_clears_the_dot() {
        const d = make();
        d.showNow();
        tryVerify(() => d.opened);
        d.recap = { weekStart: "2026-09-28", weekEnd: "2026-10-05", groups: [] };
        compare(d.taskCount, 0);
        verify(findChild(d.contentItem, "recap-group-backlog-prog") === null);
        d.close();
        tryVerify(() => !d.visible);
        compare(d.seenWeek, "2026-10-05");
    }

    function test_no_dot_once_seen_or_when_switched_off() {
        const d = make();
        AppController.appSettingsJson = JSON.stringify({ notifications: { recapSeenWeek: d.weekKey(new Date()) } });
        verify(!d.unseen, "a dot for a week already seen");
        AppController.appSettingsJson = JSON.stringify({ notifications: { weeklyRecap: false } });
        verify(!d.unseen, "a dot with the recap switched off");
        AppController.appSettingsJson = "";
        compare(d.unseen, d.hasContent);
    }

    function test_switched_off_is_never_due() {
        AppController.appSettingsJson = JSON.stringify({ notifications: { weeklyRecap: false } });
        const d = make();
        verify(!d.isDue(new Date(2026, 9, 5), tc.sample));
    }

    function test_it_lists_each_move_and_its_tasks() {
        const d = make();
        d.recap = tc.sample;
        d.open();
        tryVerify(() => d.opened);
        compare(d.taskCount, 3);
        verify(findChild(d.contentItem, "recap-group-backlog-prog") !== null);
        verify(findChild(d.contentItem, "recap-group-prog-done") !== null);
        verify(findChild(d.contentItem, "recap-task-APP-2") !== null);
        d.close();
    }

    function test_a_task_opens_and_the_recap_closes() {
        const d = make();
        d.recap = tc.sample;
        d.open();
        tryVerify(() => d.opened);
        let got = "";
        d.taskActivated.connect((id) => { got = id; });
        findChild(d.contentItem, "recap-task-area-APP-3").activated();
        compare(got, "APP-3");
        tryVerify(() => !d.visible);
    }
}
