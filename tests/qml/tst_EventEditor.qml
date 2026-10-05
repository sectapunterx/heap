// EventEditor coverage: smoke-load of the modal popup against a live
// AppController, the callable function contract (parseHour / parseHourRange /
// _formatHour / _maybeExpandRange), and showForId() pulling a saved event's
// data back out of the events model. EventEditor declares no signals and no
// objectNames, so there is no click-driven layer here.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

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
        verify(!ed.visible, "editor popup must start closed");
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

    // _maybeExpandRange: typing a range into the start field splits it across
    // start/end; a plain single time leaves both fields untouched.
    function test_maybe_expand_range() {
        const ed = make('import TodoCpp; EventEditor { }');
        const f = createTemporaryQmlObject(
            'import QtQuick; QtObject { property string text: "14:00-15:00" }', host);
        const o = createTemporaryQmlObject(
            'import QtQuick; QtObject { property string text: "" }', host);
        verify(f !== null && o !== null);

        ed._maybeExpandRange(f, o);
        compare(f.text, "14:00");
        compare(o.text, "15:00");

        f.text = "10:30";
        o.text = "keep";
        ed._maybeExpandRange(f, o);
        compare(f.text, "10:30", "single time must not be rewritten");
        compare(o.text, "keep", "other field must not be clobbered");
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

        verify(ed.visible, "showForId must open the popup");
        compare(ed.eventId, ev.id);
        compare(Qt.formatDate(ed.pickedDate, "yyyy-MM-dd"),
                Qt.formatDate(day, "yyyy-MM-dd"));

        ed.close();
        AppController.deleteEvent(ev.id);   // leave the shared profile clean
    }

    // "No type" is offered first, and an event saved with it reopens on it
    // rather than falling back to the standup the list used to start with.
    function test_untyped_event_round_trips() {
        const ed = make('import TodoCpp; EventEditor { }');
        compare(ed.types[0], "none");
        compare(ed._typeIndex("sync"), ed.types.indexOf("sync"));
        compare(ed._typeIndex("imported-kind"), 0, "unknown types read as untyped");

        const day = new Date();
        day.setDate(day.getDate() + 420);
        day.setHours(0, 0, 0, 0);
        const ev = AppController.newEventDraft(10, day);
        ev.title = "untyped probe";
        ev.type = "none";
        ev.end = 10.5;
        ev.date = day;
        AppController.saveEvent(ev);

        ed.showForId(ev.id);
        compare(ed._draft().type, "none");
        ed.close();
        AppController.deleteEvent(ev.id);
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
    // input, Save and Delete are gone, and the join link is a button.
    function test_a_subscription_meeting_opens_read_only() {
        const ed = make('import TodoCpp; EventEditor { }');
        const d = AppController.newEventDraft(10, new Date());
        d.id = "sub:probe:meeting-1";
        d.title = "Sprint sync";
        d.url = "https://talk.example.com/j/123";
        ed.showForDraft(d);
        tryVerify(() => ed.opened);
        verify(ed.readOnly);
        verify(findChild(ed, "event-readonly-banner").visible);
        verify(!findChild(ed, "event-title").enabled);
        verify(findChild(ed, "event-notes").readOnly);
        verify(findChild(ed, "event-join").visible);
        ed.close();
    }

    function test_an_own_event_is_editable() {
        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForDraft(AppController.newEventDraft(10, new Date()));
        tryVerify(() => ed.opened);
        verify(!ed.readOnly);
        verify(!findChild(ed, "event-readonly-banner").visible);
        verify(findChild(ed, "event-title").enabled);
        ed.close();
    }
}
