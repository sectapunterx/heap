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

    // Integrations settings: the catalogue is C++-driven, and switching to the
    // section must instantiate the card delegates (integrationCatalog(), the
    // auto-sync selector, I18n descKey bindings) without a QML error.
    function test_settingsview_integrations() {
        const sv = load("SettingsView");
        const cat = AppController.integrationCatalog();
        verify(cat.length >= 12, "catalog should list all providers");
        compare(cat[0].id, "github");
        // fields is a QVariantList → indexable sequence in QML (Array.isArray is
        // false for these, but the card Repeater consumes it as a model).
        verify(cat[0].fields.length > 0, "provider must expose fields");
        // A secret field is flagged so QML routes it to the keychain.
        let hasSecret = false;
        for (let i = 0; i < cat[0].fields.length; ++i) if (cat[0].fields[i].secret) hasSecret = true;
        verify(hasSecret, "github must have a secret field");
        // Render the integrations section — exercises the card delegate tree.
        sv.activeSection = "integrations";
        wait(50);
        compare(sv.activeSection, "integrations");
    }

    // Find the TextField inside a TextRow (children[0] is the label).
    function findTextField(row) {
        for (let i = 0; i < row.children.length; ++i) {
            if (row.children[i].echoMode !== undefined) return row.children[i];
        }
        return null;
    }

    // A pending edit must be flushable without Enter or focus loss: every action
    // on the Integrations card is a MouseArea, which never takes focus from the
    // field, so a freshly pasted token would otherwise still be unsaved when
    // Connect / Test connection / Sync now fires.
    function test_settings_textrow_commit_pending() {
        const row = createTemporaryQmlObject('import TodoCpp; SettingsView.TextRow { value: "old" }', host);
        verify(row !== null, "failed to instantiate SettingsView.TextRow");
        let committed = "";
        row.committed.connect(function(t) { committed = t; });

        const field = findTextField(row);
        verify(field !== null, "TextRow must contain a TextField");
        field.text = "pasted-token";
        compare(committed, "", "typing alone must not write settings");
        row.commitPending();
        compare(committed, "pasted-token");

        // Idempotent: value catches up, so a second flush is a no-op.
        row.value = "pasted-token";
        committed = "";
        row.commitPending();
        compare(committed, "");

        // Secret rows stay masked while unfocused.
        row.secret = true;
        compare(field.echoMode, TextInput.Password);
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
