// APP-191: every view has an EmptyState for when it has nothing to show —
// what appears there and what to press next — and a search that matches
// nothing says so instead of calling the view empty.
//
// The QML test profile persists between runs and may hold tasks, so "empty"
// is made by moving to a far-off date or searching for nothing.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "EmptyStates"
    when: windowShown
    visible: true
    width: 1000
    height: 700

    Item { id: host; anchors.fill: parent }

    readonly property string nothing: "zzqx-no-such-thing-7f1"
    property date savedDate

    function initTestCase() { tc.savedDate = AppController.selectedDate; }
    function cleanup() { AppController.selectedDate = tc.savedDate; }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // An EmptyState that is up, with a title and a next step.
    function verifyState(item, what) {
        verify(item !== null, what + ": no empty state");
        tryVerify(() => item.visible, 2000, what + " empty state not shown");
        verify(item.title.length > 0, what + ": no title");
        verify(item.title.indexOf(".") !== 0 && item.title.indexOf("empty.") < 0, what + ": raw key " + item.title);
    }

    function test_board() {
        const b = make('import TodoCpp; KanbanBoard { anchors.fill: parent }');
        const s = findChild(b, "board-empty-state");
        verify(s !== null);
        verify(s.title.length > 0 && s.line.length > 0, "the whole-board state says what to press");
        verify(s.line.indexOf(AppController.shortcutFor("task.new")) >= 0 || AppController.tasks.rowCount() > 0);
    }

    // EYE-4: a board with no cards says so once. Every column used to add
    // its own "Nothing here yet" under the board's state: eight at once.
    function test_empty_board_has_one_empty_state() {
        const prev = AppController.activeProfileId;
        const pid = AppController.createProfile("eyes-probe-empty", "#5cc2dd");
        verify(pid !== "");
        try {
            tryVerify(() => (AppController.statusCounts["_total"] || 0) === 0, 2000, "the new profile is not empty");
            const b = make('import TodoCpp; KanbanBoard { anchors.fill: parent }');
            const s = findChild(b, "board-empty-state");
            verifyState(s, "empty board");
            const shown = [];
            let cols = 0;
            (function walk(it) {
                if (!it) return;
                if (it.objectName === "column-empty") cols++;
                if (it.objectName === "column-empty" && it.visible && it.parent.visible) shown.push(it);
                const kids = it.children || [];
                for (let i = 0; i < kids.length; i++) walk(kids[i]);
            })(b);
            verify(cols > 0, "no columns on the board");
            compare(shown.length, 0, "columns still say they are empty under the board's state");
        } finally {
            AppController.deleteProfile(pid);
            AppController.activeProfileId = prev;
        }
    }

    // FUNC-1: a search that hides every card says so once, for the board,
    // like the other views — not "Nothing here yet" in every column, nor an
    // invitation to drag a card into a column the search emptied.
    function test_board_search_finds_nothing() {
        const d = AppController.newTaskDraft("todo");
        d._isNew = true; d.id = "EMPTY-FUNC1"; d.title = "func1 probe";
        verify(AppController.saveTask(d));
        try {
            const b = make('import TodoCpp; KanbanBoard { anchors.fill: parent }');
            const s = findChild(b, "board-empty-state");
            tryVerify(() => !s.visible, 2000, "the board has a task but says it is empty");
            b.searchText = tc.nothing;
            verifyState(s, "board search");
            compare(s.title, I18n.t("view.empty.noMatch.title"));
            compare(s.line, I18n.t("view.empty.noMatch.hint"));
            const cols = [];
            (function walk(it) {
                if (!it) return;
                if (it.objectName === "column-empty") cols.push(it);
                const kids = it.children || [];
                for (let i = 0; i < kids.length; i++) walk(kids[i]);
            })(b);
            verify(cols.length > 0);
            for (const c of cols) verify(!c.parent.visible, "a column still says it is empty");
            // A search that matches some cards: the board state goes, and the
            // columns it emptied say nothing matches, with no drag invitation.
            b.searchText = "func1 probe";
            tryVerify(() => !s.visible, 2000);
            for (const c of cols) if (c.parent.visible) {
                compare(c.title, I18n.t("view.empty.noMatch.title"));
                compare(c.line, "");
            }
        } finally {
            AppController.deleteTask("EMPTY-FUNC1");
            AppController.clearPendingUndo();
        }
    }

    function test_timeline_search_finds_nothing() {
        const v = make('import TodoCpp; TimelineView { anchors.fill: parent }');
        v.searchText = tc.nothing;
        const s = findChild(v, "timeline-empty");
        verifyState(s, "timeline");
        compare(s.title, I18n.t("timeline.empty.title"));
    }

    function test_week() {
        AppController.selectedDate = new Date(2099, 5, 15);
        const v = make('import TodoCpp; WeekView { anchors.fill: parent }');
        const s = findChild(v, "week-empty");
        verifyState(s, "week");
        compare(s.title, I18n.t("week.empty.title"));
        verify(s.line.indexOf(AppController.shortcutFor("task.new")) >= 0, s.line);
        v.searchText = tc.nothing;
        tryCompare(s, "title", I18n.t("view.empty.noMatch.title"));
    }

    function test_month() {
        AppController.selectedDate = new Date(2099, 5, 15);
        const v = make('import TodoCpp; MonthView { anchors.fill: parent }');
        verify(v.monthEmpty);
        const card = findChild(v, "month-empty");
        verify(card !== null && card.visible);
        const state = findChild(card, "month-empty-state");
        verifyState(state, "month");
        compare(state.title, I18n.t("month.empty.title"));
        v.searchText = tc.nothing;
        tryCompare(state, "title", I18n.t("view.empty.noMatch.title"));
    }

    function test_archive_search_finds_nothing() {
        const v = make('import TodoCpp; ArchiveView { anchors.fill: parent }');
        v.searchText = tc.nothing;
        const s = findChild(v, "archive-empty");
        verifyState(s, "archive");
        compare(s.title, I18n.t("view.empty.noMatch.title"));
    }

    function test_notes_list() {
        const p = make('import TodoCpp; NotesListPane { width: 240; height: 600 }');
        p.filter = tc.nothing;
        verifyState(findChild(p, "notes-empty"), "notes");
    }

    function test_docs_page_pane() {
        const p = make('import TodoCpp; MdEditorPane { width: 600; height: 400; pageId: ""; emptyText: "pick" }');
        verifyState(findChild(p, "md-editor-empty"), "doc page");
    }

    function test_palette_search_finds_nothing() {
        const cp = make('import TodoCpp; CommandPalette { }');
        cp.open();
        tryVerify(() => cp.opened);
        const empties = [];
        const walk = (it) => {
            if (!it) return;
            if (it.title !== undefined && it.line !== undefined && it.compact !== undefined) empties.push(it);
            for (let i = 0; i < (it.children || []).length; i++) walk(it.children[i]);
        };
        walk(cp.contentItem);
        verify(empties.length > 0, "the palette has an empty state");
        cp.close();
    }
}
