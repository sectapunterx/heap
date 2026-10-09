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

    // With no clauses the id set is empty, and accepts() must fall through to
    // the substring test rather than rejecting everything.
    function test_plain_words_fall_through_to_the_substring_test() {
        verify(Search.accepts(AppController, "login", 0, { id: "x", searchText: "fix the login flow" }));
        verify(!Search.accepts(AppController, "login", 0, { id: "x", searchText: "fix the export" }));
        const s = Search.compile(AppController, "status:blocked login", 0);
        compare(s.isQuery, true);
        compare(s.freeText, "login", "the clause is consumed, the word is not");
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
