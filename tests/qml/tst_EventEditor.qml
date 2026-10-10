// EventEditor (DG-120): the meeting as a right panel that saves on its own.
// The time parsing it keeps, showForId() pulling a saved event back, the
// autosave, the "When" row, the one-line input (EventCapture) and the rule
// words (EventRule.js), and the read-only subscription meeting.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp
import "../../qml/EventRule.js" as EventRule

TestCase {
    id: tc
    name: "EventEditor"
    when: windowShown
    visible: true
    width: 500
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // The popup instantiates against the live singletons; defaults hold and
    // pickedDate starts out bound to AppController.selectedDate.
    function test_smoke_load() {
        const ed = make('import TodoCpp; EventEditor { }');
        compare(ed.eventId, "");
        verify(!ed.visible, "the panel starts closed");
        compare(Qt.formatDate(ed.pickedDate, "yyyy-MM-dd"),
                Qt.formatDate(AppController.selectedDate, "yyyy-MM-dd"));
    }

    // _formatHour is the inverse of the fractional-hour model encoding.
    function test_format_hour() {
        const ed = make('import TodoCpp; EventEditor { }');
        compare(ed._formatHour(9.5), "09:30");
        compare(ed._formatHour(14), "14:00");
        compare(ed._formatHour(0), "00:00");
        compare(ed._formatHour(9.75), "09:45");
    }

    // parseHour: "HH:MM" resolves to a fractional hour via the chrono parser,
    // and the plain split(":") fallback gives the same answer, so the compare
    // holds on either path. Empty / garbage input degrades to 0.
    function test_parse_hour() {
        const ed = make('import TodoCpp; EventEditor { }');
        compare(ed.parseHour("14:30"), 14.5);
        compare(ed.parseHour("9:00"), 9);
        compare(ed.parseHour(""), 0);
        compare(ed.parseHour("garbage"), 0);
    }

    // A text field accepts any number, so parseHour has to answer with an hour
    // that exists. The saved range is clamped in C++ as well
    // (heap::cal::clampHours), but the editor must not display 99:00 back.
    //
    // Only the split(":") fallback needs the guard: the chrono path reads a
    // real QTime, so it can never hand back an hour outside 0..23 (it reads
    // "-3:00" as 3:00, which is its business, not this clamp's).
    function test_parse_hour_stays_inside_the_day() {
        const ed = make('import TodoCpp; EventEditor { }');
        compare(ed.parseHour("99:00"), 24);
        compare(ed.parseHour("25:30"), 24);
        compare(ed.parseHour("24:00"), 24);
        compare(ed.parseHour("23:59"), 23 + 59 / 60);
    }

    // TIME-22: an end at midnight is the end of the event's day. In 12h the
    // field shows it as "12:00am", which read back as 0 — before any start —
    // and the event could not be saved.
    function test_midnight_end_is_end_of_day() {
        const ed = make('import TodoCpp; EventEditor { }');
        ed.pickedDate = new Date(2026, 9, 5);
        ed.pickedEndDate = new Date(2026, 9, 5);
        compare(ed.parseEndStrict("12:00am"), 24);
        compare(ed.parseEndStrict("00:00"), 24);
        compare(ed.parseEndStrict("24:00"), 24);
        compare(ed.parseEndStrict("12:00pm"), 12);
        // Across midnight the end date says which midnight it is.
        ed.pickedEndDate = new Date(2026, 9, 6);
        compare(ed.parseEndStrict("00:00"), 0);
    }

    // parseHourRange: a numeric time range expands to [start, end]; a single
    // time or empty input yields null (the invalid-end guard). Numeric range
    // forms are locale-independent in the chrono parser (see
    // tests/test_chrono_parser.cpp Range* cases).
    function test_parse_hour_range() {
        const ed = make('import TodoCpp; EventEditor { }');
        const r = ed.parseHourRange("14:00-15:00");
        verify(r !== null, "numeric range must parse");
        compare(r[0], 14);
        compare(r[1], 15);
        verify(ed.parseHourRange("") === null, "empty input is not a range");
        verify(ed.parseHourRange("14:00") === null, "single time is not a range");
    }

    // showForId: a saved event round-trips through the events model back into
    // the editor — eventId and pickedDate reflect the stored row and the popup
    // opens. The shared test profile persists between runs, so the probe day
    // is emptied of leftover events first and the event is deleted afterwards.
    function test_show_for_id_populates_from_model() {
        const day = new Date();
        day.setDate(day.getDate() + 410);
        day.setHours(0, 0, 0, 0);

        const evs = AppController.events;
        for (let i = evs.rowCount() - 1; i >= 0; i--) {
            const idx = evs.index(i, 0);
            const d = evs.data(idx, Qt.UserRole + 7);   // DateRole
            if (d && d.getFullYear
                && d.getFullYear() === day.getFullYear()
                && d.getMonth() === day.getMonth()
                && d.getDate() === day.getDate())
                AppController.deleteEvent(String(evs.data(idx, Qt.UserRole + 1)));
        }

        const ev = AppController.newEventDraft(10, day);
        ev.title = "event-editor probe";
        ev.type = "oneone";
        ev.end = 11;
        ev.attendees = "@qa";
        ev.date = day;
        ev.context = "editor-probe-ctx";
        AppController.saveEvent(ev);

        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForId(ev.id);

        verify(ed.visible, "showForId opens the panel");
        compare(ed.eventId, ev.id);
        compare(Qt.formatDate(ed.pickedDate, "yyyy-MM-dd"),
                Qt.formatDate(day, "yyyy-MM-dd"));

        ed.close();
        AppController.deleteEvent(ev.id);   // leave the shared profile clean
    }

    // "No type" is offered first, and an event saved with it reopens on it.
    function test_untyped_event_round_trips() {
        const ed = make('import TodoCpp; EventEditor { }');
        compare(ed.types[0], "none");
        const day = new Date();
        day.setDate(day.getDate() + 420);
        day.setHours(0, 0, 0, 0);
        const ev = AppController.newEventDraft(10, day);
        ev.title = "untyped probe";
        ev.type = "imported-kind";
        ev.end = 10.5;
        ev.date = day;
        AppController.saveEvent(ev);
        ed.showForId(ev.id);
        compare(ed.type, "none", "unknown types read as untyped");
        compare(ed._draft().type, "none");
        ed.close();
        AppController.deleteEvent(ev.id);
    }

    // Edits save themselves: the title after a pause, "When" on Enter.
    function test_edits_save_themselves() {
        const day = new Date();
        day.setDate(day.getDate() + 430);
        day.setHours(0, 0, 0, 0);
        const ev = AppController.newEventDraft(10, day);
        ev.title = "autosave probe";
        ev.end = 11;
        ev.date = day;
        AppController.saveEvent(ev);
        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForId(ev.id);
        const title = findChild(ed, "event-title");
        title.text = "autosave probe renamed";
        tryVerify(() => AppController.eventById(ev.id).title === "autosave probe renamed", 3000);
        compare(ed.applyWhen("15:00-16:30"), "");
        const saved = AppController.eventById(ev.id);
        compare(saved.start, 15);
        compare(saved.end, 16.5);
        compare(Qt.formatDate(saved.date, "yyyy-MM-dd"), Qt.formatDate(day, "yyyy-MM-dd"), "a bare time keeps the day");
        compare(ed.applyWhen("qqq zzz"), I18n.t("event.when.unknown"));
        compare(ed.applyWhen(ed.whenLabel()), "", "the label read back changes nothing");
        ed.setRepeat("weekly");
        compare(AppController.eventById(ev.id).rrule, "FREQ=WEEKLY");
        ed.close();
        AppController.deleteEvent(ev.id);
    }

    // The words of a rule, and what the one-line input takes out first.
    function test_rule_words() {
        const fri = new Date(2026, 9, 9);
        if (I18n.lang === "ru") {
            compare(EventRule.describe("FREQ=WEEKLY", fri, I18n), "каждую неделю по пятницам");
            compare(EventRule.describe("FREQ=WEEKLY;INTERVAL=2", fri, I18n), "раз в 2 недели");
        }
        compare(EventRule.describe("", fri, I18n), I18n.t("event.repeat.none"));
        const x = EventRule.extract("Ретро спринта пт 16:00 на 1 ч каждые 2 недели");
        compare(x.rule, "FREQ=WEEKLY;INTERVAL=2");
        compare(x.minutes, 60);
        compare(x.text, "Ретро спринта пт 16:00");
        compare(EventRule.fromChrono("every:fri"), "FREQ=WEEKLY;BYDAY=FR");
        compare(EventRule.fromChrono("every:weekday"), "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR");
    }

    // A new meeting comes from one line, with chips for what was read.
    function test_one_line_input_makes_the_meeting() {
        const cap = make('import TodoCpp; EventCapture { }');
        const day = new Date();
        day.setDate(day.getDate() + 440);
        day.setHours(0, 0, 0, 0);
        cap.openAt({ date: day, start: 9, end: 10 });
        tryVerify(() => cap.opened);
        let made = "";
        cap.created.connect((id) => made = id);
        const input = findChild(cap.contentItem, "event-capture-input");
        input.text = "capture probe 14:00 for 30 min every 2 weeks";
        compare(cap.parsed.title, "capture probe");
        compare(cap.parsed.start, 14);
        compare(cap.parsed.end, 14.5);
        compare(cap.parsed.rule, "FREQ=WEEKLY;INTERVAL=2");
        verify(findChild(cap.contentItem, "event-capture-repeat").visible);
        cap.submit();
        tryVerify(() => made.length > 0);
        const ev = AppController.eventById(made);
        compare(ev.title, "capture probe");
        compare(ev.rrule, "FREQ=WEEKLY;INTERVAL=2");
        AppController.deleteEvent(made);
    }

    // Typing in the attendee field offers contacts; Enter takes the highlighted
    // one and leaves the caret ready for the next name. The trailing separator
    // is not saved.
    function test_attendee_suggestions_from_contacts() {
        const draft = AppController.newPersonDraft();
        draft._isNew = true;
        draft.id = "";
        draft.name = "Zeltser Quinn";
        draft.state = "idle";
        AppController.savePerson(draft);
        let pid = "";
        const cands = AppController.pingCandidates();
        for (let i = 0; i < cands.length; ++i)
            if (cands[i].name === "Zeltser Quinn") pid = cands[i].personId;
        verify(pid.length > 0, "probe person not saved");

        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForDraft(AppController.newEventDraft(10, new Date()));
        const att = findChild(ed, "event-attendees");
        const sug = findChild(ed, "event-attendee-suggest");
        verify(att !== null && sug !== null);

        att.forceActiveFocus();
        att.text = "zelt";
        att.cursorPosition = 4;
        tryVerify(() => sug.isOpen, 1000, "no suggestions for a contact's name");
        compare(sug.items[0].name, "Zeltser Quinn");

        keyClick(Qt.Key_Return);
        compare(att.text, "Zeltser Quinn, ");
        compare(att.cursorPosition, att.text.length);
        compare(ed._draft().attendees, "Zeltser Quinn");

        ed.close();
        AppController.deletePerson(pid);
    }

    // APP-118: a meeting from a calendar link opens read-only — no field takes
    // input, Delete is gone, and the join link is there.
    function test_a_subscription_meeting_opens_read_only() {
        const ed = make('import TodoCpp; EventEditor { }');
        const d = AppController.newEventDraft(10, new Date());
        d.id = "sub:probe:meeting-1";
        d.title = "Sprint sync";
        d.url = "https://talk.example.com/j/123";
        ed.showForDraft(d);
        tryVerify(() => ed.opened);
        verify(ed.readOnly);
        verify(findChild(ed, "event-saved").text.length > 0);
        verify(findChild(ed, "event-title").readOnly);
        verify(findChild(ed, "event-agenda").readOnly);
        verify(!findChild(ed, "event-delete").visible);
        verify(findChild(ed, "event-join").visible);
        ed.close();
    }

    function test_an_own_event_is_editable() {
        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForDraft(AppController.newEventDraft(10, new Date()));
        tryVerify(() => ed.opened);
        verify(!ed.readOnly);
        verify(!findChild(ed, "event-title").readOnly);
        verify(findChild(ed, "event-delete").visible);
        compare(findChild(ed, "event-saved").text, I18n.t("event.saved"));
        ed.close();
    }

    // IDIOT-CAL-2: a generated occurrence carries the master's id, which is
    // stored, so the editor took it for an override and never asked the
    // scope; a Repeat change became a one-off and was lost.
    function _series(title, offset) {
        const day = new Date();
        day.setDate(day.getDate() + offset);
        day.setHours(0, 0, 0, 0);
        const ev = AppController.newEventDraft(9, day);
        ev.title = title;
        ev.end = 10;
        ev.date = day;
        ev.rrule = "FREQ=DAILY;COUNT=5";
        AppController.saveEvent(ev);
        const third = new Date(day);
        third.setDate(third.getDate() + 2);
        const occ = AppController.eventOccurrences(third, third).filter(o => o.title === title);
        compare(occ.length, 1);
        return { ev: ev, occ: occ[0] };
    }
    function test_a_generated_occurrence_asks_the_scope_for_a_rule_change() {
        const s = tc._series("scope probe series", 460);
        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForOccurrence(s.occ);
        verify(ed._generated, "an occurrence the series made");
        ed.setRepeat("weekly");
        verify(ed.scopePrompt.opened, "the this / following / all question");
        ed.scopePrompt.answer("all");
        compare(AppController.eventSeriesMaster(s.ev.id).rrule.indexOf("FREQ=WEEKLY") >= 0, true);
        ed.close();
        AppController.deleteEvent(s.ev.id);
    }
    // IDIOT-CAL-1: opened on its own day, Delete asks the scope; Esc keeps
    // the series.
    function test_delete_on_an_occurrence_asks_the_scope() {
        const s = tc._series("delete scope probe", 470);
        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForOccurrence(s.occ);
        compare(Qt.formatDate(ed.pickedDate, "yyyy-MM-dd"), Qt.formatDate(s.occ.occurrenceDate, "yyyy-MM-dd"));
        ed.deleteEvent();
        verify(ed.scopePrompt.opened);
        ed.scopePrompt.close();
        verify(AppController.eventById(s.ev.id).id === s.ev.id, "cancel keeps the series");
        ed.close();
        AppController.deleteEvent(s.ev.id);
    }
}
