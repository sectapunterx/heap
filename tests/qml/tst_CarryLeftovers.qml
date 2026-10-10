// Carrying leftovers by hand (APP-248): from the end-of-day summary and from
// a selection, only on a click, one undo step, the deadline left alone.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "CarryLeftovers"
    when: windowShown
    visible: true
    width: 1000
    height: 800

    Item { id: host; anchors.fill: parent }

    function sameDay(a, b) {
        return !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function plusDays(n) {
        const t = AppController.today;
        return new Date(t.getFullYear(), t.getMonth(), t.getDate() + n);
    }
    property var _made: []
    function seed(id, fields) {
        AppController.deleteTask(id);
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.id = id;
        d.title = id + " leftover";
        for (const k in fields) d[k] = fields[k];
        verify(AppController.saveTask(d), "seeding " + id);
        tc._made.push(id);
    }
    function init() { tc._made = []; }
    function cleanup() {
        AppController.clearSelection();
        for (let i = 0; i < tc._made.length; i++) AppController.deleteTask(tc._made[i]);
        AppController.clearPendingUndo();
    }

    function test_end_of_day_carries_a_leftover_to_tomorrow_and_undo_restores() {
        const yesterday = plusDays(-1);
        const due = plusDays(10);
        seed("CARRY-1", { scheduledAt: new Date(yesterday.getFullYear(), yesterday.getMonth(), yesterday.getDate(), 11, 30),
                          scheduledHasTime: true, dueAt: due, dueHasTime: false });
        const dlg = createTemporaryQmlObject('import TodoCpp; EndOfDayDialog {}', host);
        dlg.showNow();
        tryVerify(() => dlg.opened, 2000);
        verify(dlg.summary.carryOver.some(r => r.id === "CARRY-1"), "a leftover is listed");
        const row = findChild(dlg.contentItem, "end-of-day-carry-CARRY-1");
        verify(row !== null && row.visible, "with its buttons");
        const btn = findChild(row, "end-of-day-carry-tomorrow");
        verify(btn !== null && btn.visible);
        // A real click, once the dialog has finished opening.
        tryVerify(() => !dlg.enter || !dlg.enter.running, 2000);
        wait(50);
        mouseClick(btn);
        const t = AppController.taskById("CARRY-1");
        verify(sameDay(t.scheduledAt, plusDays(1)), "→ tomorrow");
        compare(t.scheduledAt.getHours(), 11);
        compare(t.scheduledAt.getMinutes(), 30);
        verify(sameDay(t.dueAt, due), "the deadline is not touched");
        verify(!dlg.summary.carryOver.some(r => r.id === "CARRY-1"), "it leaves the list");
        AppController.undo();
        verify(sameDay(AppController.taskById("CARRY-1").scheduledAt, yesterday), "one undo puts it back");
        dlg.close();
    }

    function test_a_selection_goes_to_someday_from_the_bar() {
        seed("CARRY-2", { scheduledAt: plusDays(0), scheduledHasTime: false });
        seed("CARRY-3", { scheduledAt: plusDays(-2), scheduledHasTime: false });
        AppController.setSelectedTaskIds(["CARRY-2", "CARRY-3"]);
        const bar = createTemporaryQmlObject('import TodoCpp; SelectionBar {}', host);
        // The carry left the bar for the command line (DG-026): the bar
        // still opens its menu ("Перенести выбранные…").
        bar.openCarry();
        const menu = findChild(bar, "sel-carry-menu");
        tryVerify(() => menu.opened, 2000, "the carry menu opens");
        menu.close();
        // What the menu's "→ Someday" row runs.
        bar.carry("someday");
        for (const id of ["CARRY-2", "CARRY-3"]) {
            const t = AppController.taskById(id);
            verify(t.someday, id + " is someday");
            verify(!t.scheduledAt || isNaN(t.scheduledAt.getTime()), id + " has no day");
        }
    }

    function test_nothing_moves_without_a_click() {
        seed("CARRY-4", { scheduledAt: plusDays(-3), scheduledHasTime: false });
        const dlg = createTemporaryQmlObject('import TodoCpp; EndOfDayDialog {}', host);
        dlg.showNow();
        tryVerify(() => dlg.opened, 2000);
        dlg.close();
        verify(sameDay(AppController.taskById("CARRY-4").scheduledAt, plusDays(-3)), "opening the summary changes nothing");
    }
}
