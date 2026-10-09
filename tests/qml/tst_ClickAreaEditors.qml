// Design audit DES-19 / DES-20 / DES-25 in the editors, Docs and the markdown
// view: the hand-drawn buttons that were a bare MouseArea are ClickAreas now,
// so each is on the Tab path, has a name, and runs on Return. Also the themed
// All-day switch and the comment link that underlines instead of fading.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ClickAreaEditors"
    when: windowShown
    visible: true
    width: 1000
    height: 760

    Item { id: host; anchors.fill: parent }

    MdDocument {
        id: doc
        palette: ({ "text": "#ffffff", "link": "#4488ff" })
    }
    MdView {
        id: mdView
        width: 400; height: 200
        document: doc
    }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }
    // The ClickArea inside a hand-drawn control (its only child with `label`).
    function clickAreaIn(item) {
        const kids = item ? item.children : [];
        for (let i = 0; i < kids.length; i++)
            if (kids[i] && kids[i].label !== undefined && kids[i].activated !== undefined) return kids[i];
        return null;
    }
    // The DatePickerPopup next to a date button.
    function pickerNextTo(item) {
        const d = item.data;
        for (let i = 0; i < d.length; i++)
            if (d[i] && d[i].openAt !== undefined) return d[i];
        return null;
    }
    function onTabPathAndNamed(ca, what) {
        verify(ca !== null, what + ": no ClickArea");
        verify(ca.activeFocusOnTab, what + " is not on the Tab path");
        verify(String(ca.Accessible.name).length > 0, what + " has no accessible name");
    }

    // ── TaskEditor ──────────────────────────────────────────────────────

    function test_task_deadline_calendar_opens_from_the_keyboard() {
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor(AppController.newTaskDraft("todo"));
        tryVerify(() => te.opened, 2000);
        const ca = findChild(te.contentItem, "te-deadline-pick");
        onTabPathAndNamed(ca, "deadline calendar button");
        compare(ca.Accessible.name, I18n.t("editor.a11y.pickDeadline"));
        const picker = pickerNextTo(ca.parent);
        verify(picker !== null);
        ca.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        tryVerify(() => picker.opened, 1000, "Return on the calendar button did not open the picker");
        picker.close();
        te.close();
    }

    // DES-25: the link keeps accentStrong and shows hover with an underline.
    function test_comment_link_keeps_its_colour_and_is_named() {
        const te = make('import TodoCpp; TaskEditor { }');
        te.showFor(AppController.newTaskDraft("todo"));
        te._comments = [{ author: "ann", url: "https://example.com/c/1", body: "hi" }];
        let link = null;
        tryVerify(() => (link = findChild(te.contentItem, "te-comment-link")) !== null, 1000);
        compare(String(link.color), String(Theme.accentStrong));
        verify(!link.font.underline, "underlined at rest");
        const ca = clickAreaIn(link);
        verify(ca !== null);
        compare(ca.Accessible.role, Accessible.Link);
        verify(String(ca.Accessible.name).indexOf("ann") >= 0, "name: " + ca.Accessible.name);
        te.close();
    }

    // ── EventEditor ─────────────────────────────────────────────────────

    function test_event_date_button_opens_from_the_keyboard() {
        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForDraft(AppController.newEventDraft(10, new Date()));
        tryVerify(() => ed.opened, 2000);
        const ca = findChild(ed.contentItem, "event-date-pick");
        onTabPathAndNamed(ca, "event date button");
        verify(ca.Accessible.name.indexOf(I18n.t("editor.label.date")) === 0, "name: " + ca.Accessible.name);
        const picker = pickerNextTo(ca.parent);
        ca.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        tryVerify(() => picker.opened, 1000, "Return on the date button did not open the picker");
        picker.close();
        const end = findChild(ed.contentItem, "event-enddate");
        onTabPathAndNamed(clickAreaIn(end), "event end-date button");
        ed.close();
    }

    // DES-20: the All-day switch paints with the theme, not Basic's greys.
    function test_all_day_switch_is_themed() {
        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForDraft(AppController.newEventDraft(10, new Date()));
        tryVerify(() => ed.opened, 2000);
        const sw = findChild(ed.contentItem, "event-allday");
        const track = findChild(ed.contentItem, "event-allday-track");
        const knob = findChild(ed.contentItem, "event-allday-knob");
        verify(sw !== null && track !== null && knob !== null);
        compare(sw.Accessible.name, I18n.t("editor.label.allDay"));
        ed.allDay = false;
        compare(String(track.color), String(Theme.panel3));
        compare(String(track.border.color), String(Theme.fieldBorder));
        compare(String(knob.color), String(Theme.knob));
        compare(String(knob.border.color), String(Theme.fieldBorder));
        ed.allDay = true;
        compare(String(track.color), String(Theme.accent));
        // APP-175: the knob slides by transform; its x never moves.
        compare(knob.x, 2);
        tryVerify(() => knob.mapToItem(track, 0, 0).x === track.width - knob.width - 2, 1000,
                  "the knob ends at the right edge");
        ed.close();
    }

    function test_open_link_pill_has_a_name() {
        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForDraft(AppController.newEventDraft(10, new Date()));
        tryVerify(() => ed.opened, 2000);
        const pill = findChild(ed.contentItem, "event-link-open");
        verify(pill !== null);
        compare(pill.Accessible.name, I18n.t("event.a11y.openLink"));
        ed.close();
    }

    // ── DocsView ────────────────────────────────────────────────────────

    // ── MdView ──────────────────────────────────────────────────────────

    function test_markdown_task_box_is_a_named_checkbox() {
        const view = mdView;
        doc.text = "- [ ] ship the release\n";
        doc.flush();
        let box = null;
        tryVerify(() => (box = findChild(view, "mdTaskClick")) !== null, 1000);
        onTabPathAndNamed(box, "task box");
        compare(box.Accessible.role, Accessible.CheckBox);
        verify(!box.checked);
        compare(box.Accessible.name, "ship the release");
    }

    // ── Swatches ────────────────────────────────────────────────────────

    function test_profile_swatch_is_a_named_radio() {
        const pe = make('import TodoCpp; ProfileEditor { }');
        pe.showCreate();
        tryVerify(() => pe.opened, 1000);
        let sw = null;
        const find = (it) => {
            if (!it || sw) return;
            if (it.label !== undefined && it.role === Accessible.RadioButton) { sw = it; return; }
            for (let i = 0; i < it.children.length; i++) find(it.children[i]);
        };
        find(pe.contentItem);
        verify(sw !== null, "no swatch ClickArea");
        verify(sw.activeFocusOnTab);
        compare(sw.Accessible.name, I18n.t("swatch.name").arg(1));
        pe.close();
    }
}
