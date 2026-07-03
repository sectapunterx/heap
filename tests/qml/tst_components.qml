// Component load-smoke for the real UI (HEAP-49).
//
// Instantiates each top-level QML component from the TodoCpp module against a
// live AppController (linked via heap_core). A component that references a
// removed property, a renamed signal, or a missing type fails to instantiate
// and createTemporaryQmlObject returns null — so this catches whole classes of
// UI regressions the pure-logic tests can't see.
//
// Delegates that declare `required property` (TaskCard, …) are intentionally
// omitted: they cannot be instantiated standalone without their row context.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ComponentsLoad"
    when: windowShown
    visible: true
    width: 400
    height: 400

    Item { id: host; anchors.fill: parent }

    function load(typeName) {
        const o = createTemporaryQmlObject('import TodoCpp; ' + typeName + ' { }', host);
        verify(o !== null, "failed to instantiate " + typeName);
        return o;
    }

    function test_siderail()    { load("SideRail"); }
    function test_filterbar()   { load("FilterBar"); }
    function test_kanbanboard() { load("KanbanBoard"); }
    function test_timelineview(){ load("TimelineView"); }
    function test_weekview()    { load("WeekView"); }
    function test_daycalendar() { load("DayCalendar"); }
    function test_peoplelist()  { load("PeopleList"); }
    function test_archiveview() { load("ArchiveView"); }
    function test_docsview()    { load("DocsView"); }
    function test_notesview()   { load("NotesView"); }
    function test_settingsview(){ load("SettingsView"); }
    function test_toast()       { load("Toast"); }
    function test_topbar()      { load("TopBar"); }
    function test_selectionbar(){ load("SelectionBar"); }
    function test_commandpalette() { load("CommandPalette"); }

    // FilterBar signal contract: togglePriority carries the priority id.
    function test_filterbar_toggle_signal() {
        const fb = load("FilterBar");
        let got = "";
        fb.togglePriority.connect(function(p) { got = p; });
        fb.togglePriority("P1");
        compare(got, "P1");
    }

    // SideRail integration: focusStatusColumn drives AppController view state
    // (the wiring the ⊘/⎇ buttons use). Exercises the live singleton the rail
    // component binds to.
    function test_siderail_focus_status_integration() {
        load("SideRail");
        AppController.currentView = "notes";
        AppController.focusStatusColumn("blocked");
        compare(AppController.currentView, "board");
        compare(AppController.focusedStatus, "blocked");
    }
}
