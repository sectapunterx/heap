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
    // Wider than the small layout (Theme.compactWindowWidth).
    width: 1500
    height: 800

    Item { id: host; anchors.fill: parent }
    property var tasks: []
    property var events: []
    property date savedDate
    function initTestCase() {
        tc.savedDate = AppController.selectedDate;
        // A fresh test profile is the first run (FirstRunHero); these tests
        // look at the day itself.
        AppController.markWelcomeSeen();
    }
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

    // R3-001: a task due today that also has a block in the day is still
    // listed under the deadlines, as the facts line counts it.
    function test_a_planned_deadline_is_still_listed() {
        const day = tc.probeDay();
        const d = AppController.newTaskDraft("todo");
        d._isNew = true;
        d.title = "planned and due probe";
        d.scheduledAt = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 11, 0);
        d.scheduledHasTime = true;
        d.dueAt = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 18, 0);
        d.dueHasTime = true;
        verify(AppController.saveTask(d));
        tc.tasks.push(d.id);
        const data = AppController.todayData(day, false);
        verify(data.blocks.some(b => b.id === d.id), "the task has a block in the day");
        verify(data.deadlines.some(t => t.id === d.id), "and is listed under the deadlines");
        verify(data.facts.dueToday >= 1);
    }

    function test_an_empty_day_says_so_in_one_line() {
        AppController.selectedDate = tc.probeDay();
        const v = createTemporaryQmlObject('import TodoCpp; TodayView { anchors.fill: parent }', host);
        compare(findChild(v, "today-facts").text, I18n.t("today.nothing"));
        // DG-010: no second "load" line under the facts.
        compare(findChild(v, "today-load"), null);
    }

    function probeMeeting(day) {
        const ev = AppController.newEventDraft(10, day);
        ev.title = "today probe sync";
        ev.type = "sync";
        ev.end = 10.5;
        ev.date = day;
        ev.attendees = "Zoom";
        AppController.saveEvent(ev);
        tc.events.push(ev.id);
    }

    // DG-012: quiet draws plain rows with an icon and a lowercase caption,
    // bold the cards with "Встреча"; the arrows are boxed only in bold.
    function test_quiet_and_bold_draw_the_day_their_own_way() {
        const saved = AppController.appSettingsJson;
        try {
            const day = tc.probeDay();
            AppController.selectedDate = day;
            tc.probeMeeting(day);
            Style.apply("quiet");
            const v = createTemporaryQmlObject('import TodoCpp; TodayView { width: 1300; height: 800 }', host);
            verify(v.plain, "quiet is not plain");
            const m = v.rows.filter(r => r.kind === "meeting")[0];
            verify(!!m, "no meeting row");
            compare(v._sub("meeting", m.block), [I18n.t("today.q.meeting"), I18n.fmtMinutes(30), "Zoom"].join(" · "));
            compare(findChild(v, "today-prev").border.width, 0, "quiet arrows are boxed");
            Style.apply("bold");
            verify(!v.plain);
            compare(v._sub("meeting", m.block), [I18n.t("event.kind.meeting"), "Zoom"].join(" · "));
            compare(findChild(v, "today-prev").border.width, 1);
        } finally {
            AppController.appSettingsJson = saved;
        }
    }

    // DG-014: bold shows one in-progress card; the rest are lines.
    function test_one_card_for_what_is_in_progress() {
        const saved = AppController.appSettingsJson;
        try {
            Style.apply("bold");
            for (const n of ["a", "b"]) {
                const d = AppController.newTaskDraft("prog");
                d._isNew = true;
                d.title = "in progress probe " + n;
                AppController.saveTask(d);
                tc.tasks.push(d.id);
            }
            const v = createTemporaryQmlObject('import TodoCpp; TodayView { width: 1300; height: 800 }', host);
            verify(v.inProgress.length >= 2, "fewer than two in progress");
            verify(findChild(v, "today-lead").visible);
            compare(v.otherInProgress.length, v.inProgress.length - 1);
        } finally {
            AppController.appSettingsJson = saved;
        }
    }

    function test_wrote_is_past_tense() {
        if (I18n.lang === "ru") compare(I18n.t("today.wrote"), "Написал");
        else compare(I18n.t("today.wrote"), "Wrote");
    }

    // The weekly recap is offered on the week's last working day only
    // (Mon-Fri by default: Friday yes, Thursday and Saturday no).
    function test_the_recap_line_is_on_the_last_working_day() {
        compare(AppController.todayData(new Date(2026, 9, 9), false).recapDay, true, "Friday");
        compare(AppController.todayData(new Date(2026, 9, 8), false).recapDay, false, "Thursday");
        compare(AppController.todayData(new Date(2026, 9, 10), false).recapDay, false, "Saturday");
    }

    // IDIOT-CAL-1: Return on a meeting of a series hands its day's occurrence
    // up, not null (which opened the whole series on its first day).
    function test_a_series_meeting_opens_its_occurrence() {
        const day = tc.probeDay();
        const first = new Date(day); first.setDate(first.getDate() - 3);
        const ev = AppController.newEventDraft(8, first);
        ev.title = "today series probe";
        ev.end = 8.5;
        ev.date = first;
        ev.rrule = "FREQ=DAILY";
        AppController.saveEvent(ev);
        tc.events.push(ev.id);
        AppController.selectedDate = day;
        const v = createTemporaryQmlObject('import TodoCpp; TodayView { anchors.fill: parent }', host);
        const spy = createTemporaryQmlObject('import QtTest; SignalSpy { signalName: "eventClicked" }', host);
        spy.target = v;
        v.moveCursor(0, 0);
        const items = v._items();
        const at = items.findIndex(it => it.id === ev.id);
        verify(at >= 0, "the meeting is a cursor stop");
        v._placeIdx(at);
        v.openCursor();
        compare(spy.count, 1);
        compare(spy.signalArguments[0][1], Qt.formatDate(day, "yyyy-MM-dd"));
    }
}
