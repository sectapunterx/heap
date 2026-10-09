// The day's summary (APP-190, qml/EndOfDayDialog.qml): what it lists from
// AppController.endOfDaySummaryAt(now), that it changes nothing, and that a
// task in it opens. Which tasks land in which list is tested in C++
// (test_safety_net.cpp, test_safety_appcontroller.cpp).
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "EndOfDayDialog"
    when: windowShown
    visible: true
    width: 800
    height: 700

    Item { id: host; anchors.fill: parent }

    readonly property string probe: "eod-probe-" + Date.now()
    property var made: []

    function cleanup() {
        for (const id of tc.made) AppController.deleteTask(id);
        tc.made = [];
    }

    function addTask(status, fields) {
        const draft = AppController.newTaskDraft(status);
        draft._isNew = true;
        draft.title = tc.probe + " " + (fields.title || status);
        Object.assign(draft, fields, { title: tc.probe + " " + (fields.title || status) });
        verify(AppController.saveTask(draft), "saveTask");
        tc.made = tc.made.concat([draft.id]);
        return draft.id;
    }

    function make() {
        const d = createTemporaryQmlObject('import TodoCpp; EndOfDayDialog {}', host);
        verify(d !== null);
        return d;
    }

    function rowIds(list) { return (list || []).map(r => r.id); }

    function test_it_lists_closed_carry_over_and_timers() {
        const now = new Date(); now.setHours(18, 30, 0, 0);
        const dueToday = new Date(now); dueToday.setHours(17, 0, 0, 0);
        const dueTomorrow = new Date(now); dueTomorrow.setDate(dueTomorrow.getDate() + 1);
        const carry = addTask("todo", { title: "carry", dueAt: dueToday, dueHasTime: true });
        const later = addTask("todo", { title: "later", dueAt: dueTomorrow, dueHasTime: true });
        const closed = addTask("todo", { title: "closed" });
        AppController.moveTask(closed, "done");
        const timed = addTask("prog", { title: "timed" });
        AppController.startTaskTimer(timed);

        const s = AppController.endOfDaySummaryAt(now);
        verify(rowIds(s.closed).indexOf(closed) >= 0, "closed today: " + JSON.stringify(s.closed));
        verify(rowIds(s.carryOver).indexOf(carry) >= 0, "due today carries over");
        verify(rowIds(s.carryOver).indexOf(later) < 0, "due tomorrow is not today's");
        verify(rowIds(s.timers).indexOf(timed) >= 0, "running timer");
        const t = s.timers.filter(r => r.id === timed)[0];
        verify(t.since && t.since.getTime && !isNaN(t.since.getTime()), "a timer says since when");

        const d = make();
        d.summary = s;
        d.open();
        tryCompare(d, "opened", true);
        verify(!d.empty);
        for (const key of ["carryOver", "timers"]) {
            const sec = findChild(d.contentItem, "end-of-day-" + key);
            verify(sec !== null && sec.visible, key + " section shown");
        }
        // Closed today is a count in the facts line, not a list (DG-124).
        const facts = findChild(d.contentItem, "end-of-day-facts");
        verify(facts.text.indexOf(I18n.t("eod.fact.closed").arg(s.closed.length)) === 0, facts.text);
        verify(findChild(d.contentItem, "end-of-day-task-" + carry) !== null);
        verify(findChild(d.contentItem, "end-of-day-timer-" + timed) !== null);

        // It only reads.
        compare(AppController.taskById(carry).status, "todo");
        compare(AppController.taskById(carry).dueAt.getTime(), dueToday.getTime());
        verify(AppController.taskById(timed).isTiming, "the timer still runs");
        AppController.stopTaskTimer(timed);
        d.close();
    }

    function test_an_empty_day_says_so() {
        const d = make();
        d.summary = { date: new Date(), closed: [], carryOver: [], timers: [] };
        d.open();
        tryCompare(d, "opened", true);
        verify(d.empty);
        compare(findChild(d.contentItem, "end-of-day-facts").text, I18n.t("eod.empty"));
        d.close();
    }

    function test_a_task_opens_and_the_summary_closes() {
        const d = make();
        d.summary = { date: new Date(), closed: [], carryOver: [{ id: "APP-1", title: "one" }], timers: [] };
        let opened = "";
        d.taskActivated.connect(id => opened = id);
        d.open();
        tryCompare(d, "opened", true);
        const row = findChild(d.contentItem, "end-of-day-task-area-APP-1");
        verify(row !== null);
        row.activated();
        compare(opened, "APP-1");
        tryCompare(d, "opened", false);
    }
}
