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
}
