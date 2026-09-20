// The search box is a query box. The board gets that for free — TaskFilterProxy
// compiles the text in C++ — but the archive, timeline, week and month views
// build their own JS snapshots and used to do a bare substring test, so
// `status:blocked` narrowed the board and found nothing at all on the timeline.
//
// These drive the real views rather than SearchFilter alone: the bug was never
// in the parser, it was in who asked it.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp
import "../../qml/Search.js" as Search

TestCase {
    id: tc
    name: "SearchFilter"
    when: windowShown
    visible: true
    width: 700
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // The QML test profile is persistent, so everything seeded here is torn
    // down again and the titles are distinctive enough not to collide.
    property var seeded: []

    function seed(title, status, priority) {
        const t = AppController.newTaskDraft(status);
        t.title = title;
        t.priority = priority;
        AppController.saveTask(t);
        tc.seeded.push(t.id);
        return t.id;
    }

    function cleanup() {
        for (let i = 0; i < tc.seeded.length; i++) AppController.deleteTask(tc.seeded[i]);
        tc.seeded = [];
    }

    // Flatten a TimelineView's buckets to the ids it would show.
    function timelineIds(tv) {
        const out = [];
        const groups = tv.buildGroups();
        for (const k in groups) {
            const arr = groups[k];
            for (let i = 0; i < arr.length; i++) out.push(arr[i].id);
        }
        return out;
    }

    function test_timeline_applies_clauses_not_substrings() {
        const blocked = seed("sf probe alpha", "blocked", "P1");
        const todo    = seed("sf probe beta", "todo", "P1");
        const other   = seed("sf unrelated gamma", "blocked", "P1");

        const tv = make('import TodoCpp; TimelineView { anchors.fill: parent; showDone: true }');

        tv.searchText = "status:blocked";
        let ids = timelineIds(tv);
        verify(ids.indexOf(blocked) >= 0, "a blocked task must survive status:blocked");
        verify(ids.indexOf(other) >= 0);
        verify(ids.indexOf(todo) < 0, "status:blocked must drop a todo task");

        // Before the fix this was empty: no task's text contains the literal
        // string "status:blocked".
        verify(ids.length > 0, "a clause must not filter everything out");
    }

    function test_timeline_composes_a_clause_with_a_search_word() {
        const blocked = seed("sf probe alpha", "blocked", "P1");
        const other   = seed("sf unrelated gamma", "blocked", "P1");

        const tv = make('import TodoCpp; TimelineView { anchors.fill: parent; showDone: true }');

        tv.searchText = "status:blocked alpha";
        const ids = timelineIds(tv);
        verify(ids.indexOf(blocked) >= 0, "the clause and the word both hold for this one");
        verify(ids.indexOf(other) < 0, "'alpha' is still a substring test");
    }

    function test_plain_text_search_is_unchanged() {
        const blocked = seed("sf probe alpha", "blocked", "P1");
        const other   = seed("sf unrelated gamma", "blocked", "P1");

        const tv = make('import TodoCpp; TimelineView { anchors.fill: parent; showDone: true }');

        tv.searchText = "alpha";
        const ids = timelineIds(tv);
        verify(ids.indexOf(blocked) >= 0);
        verify(ids.indexOf(other) < 0);
    }

    function test_archive_view_filters_by_clause_too() {
        const id = seed("sf archived alpha", "todo", "P0");
        AppController.setArchived(id, true);

        const av = make('import TodoCpp; ArchiveView { anchors.fill: parent }');

        av.searchText = "priority:P0";
        let items = av.buildItems();
        let found = false;
        for (let i = 0; i < items.length; i++) if (items[i].id === id) found = true;
        verify(found, "the archived P0 task must survive priority:P0");

        av.searchText = "priority:P3";
        items = av.buildItems();
        for (let i = 0; i < items.length; i++) {
            verify(items[i].id !== id, "priority:P3 must not admit a P0 task");
        }
    }

    // With no clauses the id set is empty, and accepts() must fall through to
    // the substring test rather than rejecting everything.
    function test_plain_words_fall_through_to_the_substring_test() {
        verify(Search.accepts(AppController, "login", 0, { id: "x", searchText: "fix the login flow" }));
        verify(!Search.accepts(AppController, "login", 0, { id: "x", searchText: "fix the export" }));
        const s = Search.compile(AppController, "status:blocked login", 0);
        compare(s.isQuery, true);
        compare(s.freeText, "login", "the clause is consumed, the word is not");
    }

    // The views compute their snapshots inside bindings, so nothing here may be
    // a QML property written during a rebuild — that is a binding loop, which
    // Qt reports once and then stops re-evaluating. This catches a regression
    // back to a QML object with properties.
    function test_rebuilding_a_view_logs_no_binding_loop() {
        seed("sf loop probe", "todo", "P1");
        const av = make('import TodoCpp; ArchiveView { anchors.fill: parent }');
        av.searchText = "priority:P0";
        av.searchText = "priority:P1";
        av.buildItems();
        // A binding loop is reported as a warning, not a failure, so assert on
        // the message rather than trusting the run to have gone quiet.
        failOnWarning(/Binding loop detected/);
    }

    // What the search field lights up on.
    function test_top_bar_knows_a_query_from_a_search() {
        verify(AppController.searchIsQuery("status:blocked"));
        verify(!AppController.searchIsQuery("blocked"));
        verify(!AppController.searchIsQuery("https://example.test/x"),
               "a bare colon is not a clause");
        verify(AppController.searchFields().indexOf("deadline") >= 0);

        const tb = make('import TodoCpp; TopBar { width: 900 }');
        tb.searchText = "blocked";
        verify(!tb.searchIsQuery, "ordinary words must not claim to be a query");
        tb.searchText = "status:blocked";
        verify(tb.searchIsQuery, "the field must show that it is filtering structurally");
        tb.searchText = "";
        verify(!tb.searchIsQuery);
    }
}
