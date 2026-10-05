// The Monday recap (WEAK PECAP, qml/WeeklyRecapDialog.qml): when it opens by
// itself, that it opens once a week, and what it lists. The grouping itself is
// AppController::weeklyRecapFor's and is tested in C++.
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
