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

    // ── EventEditor (DG-120: the panel) ───────────────────────────────

    // The rows that open a menu are on the Tab path and named.
    function test_event_rows_open_from_the_keyboard() {
        const ed = make('import TodoCpp; EventEditor { }');
        ed.showForDraft(AppController.newEventDraft(10, new Date()));
        tryVerify(() => ed.opened, 2000);
        for (const name of ["event-repeat", "event-reminder", "event-profile", "event-task"]) {
            const row = findChild(ed, name);
            verify(row !== null, name);
            verify(row.activeFocusOnTab, name + " is not on the Tab path");
        }
        compare(clickAreaIn(findChild(ed, "event-join")).Accessible.name, I18n.t("event.join"));
        ed.close();
    }

    // ── DocsView ────────────────────────────────────────────────────────

    function test_docs_search_clear_runs_on_return() {
        const dv = make('import TodoCpp; DocsView { anchors.fill: parent }');
        dv.searchText = "zzz";
        const ca = findChild(dv, "docs-search-clear");
        tryVerify(() => ca.visible, 1000);
        onTabPathAndNamed(ca, "search clear button");
        ca.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        compare(dv.searchText, "");
    }

    function test_docs_controls_are_on_the_tab_path() {
        const dv = make('import TodoCpp; DocsView { anchors.fill: parent }');
        dv.tab = "references";
        onTabPathAndNamed(findChild(dv, "docs-new-section"), "new section button");
        compare(findChild(dv, "docs-new-section").Accessible.name, I18n.t("docs.newSection"));
        if (dv.snippets.length > 0) {
            tryVerify(() => findChild(dv, "docs-snippet-copy") !== null, 1000);
            onTabPathAndNamed(findChild(dv, "docs-snippet-copy"), "snippet copy button");
            // ✎ / × stay on the Tab path while hidden (IconButton).
            verify(findChild(dv, "docs-snippet-edit").activeFocusOnTab);
            verify(findChild(dv, "docs-snippet-delete").activeFocusOnTab);
        }
        if (dv.sections.length > 0 && dv.sections[0].items.length > 0) {
            tryVerify(() => findChild(dv, "docs-card-open") !== null, 1000);
            onTabPathAndNamed(findChild(dv, "docs-card-open"), "doc card");
        }
    }

    // Pages | References switch from the keyboard and say which is on.
    function test_docs_tabs_switch_on_return() {
        const dv = make('import TodoCpp; DocsView { anchors.fill: parent }');
        dv.tab = "pages";
        const ca = clickAreaIn(findChild(dv, "docs-tab-references"));
        onTabPathAndNamed(ca, "References tab");
        verify(!ca.checked);
        ca.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Return);
        compare(dv.tab, "references");
        verify(ca.checked);
    }

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
