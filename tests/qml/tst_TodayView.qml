// Today (APP-260): the day by the hours, facts with only the non-zero parts,
// plurals through I18n, the side sections hidden when empty.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TodayView"
    when: windowShown
    visible: true
    width: 1300
    height: 800

    Item { id: host; anchors.fill: parent }
    property var tasks: []
    property var events: []
    property date savedDate
    function initTestCase() { tc.savedDate = AppController.selectedDate; }
    function cleanup() {
        for (const id of tc.tasks) AppController.deleteTask(id);
        for (const id of tc.events) AppController.deleteEvent(id);
        tc.tasks = []; tc.events = [];
        AppController.clearPendingUndo();
        AppController.selectedDate = tc.savedDate;
    }
    // A Wednesday a year ahead: nothing of the demo on it.
    function probeDay() {
        const d = new Date(); d.setFullYear(d.getFullYear() + 1); d.setHours(0, 0, 0, 0);
        while (d.getDay() !== 3) d.setDate(d.getDate() + 1);
        return d;
    }

    function test_plurals() {
        if (I18n.lang === "ru") {
            compare(I18n.count(1, "today.n.meetings"), "1 встреча");
            compare(I18n.count(3, "today.n.meetings"), "3 встречи");
            compare(I18n.count(5, "today.n.meetings"), "5 встреч");
            compare(I18n.count(11, "today.n.meetings"), "11 встреч");
            compare(I18n.count(21, "today.n.meetings"), "21 встреча");
        } else {
            compare(I18n.count(1, "today.n.meetings"), "1 meeting");
            compare(I18n.count(2, "today.n.meetings"), "2 meetings");
        }
    }

    function test_the_day_shows_blocks_free_time_and_facts() {
        const day = tc.probeDay();
        AppController.selectedDate = day;
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.title = "today probe";
        d.scheduledAt = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 14, 0);
        d.scheduledHasTime = true;
        d.estimateMinutes = 90;
        AppController.saveTask(d);
        tc.tasks.push(d.id);
        const v = createTemporaryQmlObject('import TodoCpp; TodayView { anchors.fill: parent }', host);
        const kinds = v.rows.map(r => r.kind);
        verify(kinds.indexOf("task") >= 0, kinds);
        verify(kinds.indexOf("free") >= 0, "no free window: " + kinds);
        verify(kinds.indexOf("end") >= 0, "no end of the working day");
        verify(kinds.indexOf("now") < 0, "a day to come has no now line");
        const facts = findChild(v, "today-facts").text;
        compare(facts, I18n.count(1, "today.n.planned"), "only the non-zero parts");
        verify(findChild(v, "today-back").visible, "another day offers the way back");
        compare(v.dayData.load.tasks, 90);
    }

    function test_an_empty_day_says_so_in_one_line() {
        AppController.selectedDate = tc.probeDay();
        const v = createTemporaryQmlObject('import TodoCpp; TodayView { anchors.fill: parent }', host);
        compare(findChild(v, "today-facts").text, I18n.t("today.nothing"));
    }
}
