// The calendar + people column is resizable from its left edge, and the
// left sidebar folds between labels and icons. Both are remembered in
// settings. Instantiates the real Main.qml so the wiring is what ships.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "RightPanelResize"
    when: windowShown

    property var win: null
    property string savedSettings: ""

    function initTestCase() {
        tc.savedSettings = AppController.appSettingsJson;
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        verify(comp.status === Component.Ready, comp.errorString());
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        tc.win.width = 1600;
        tc.win.height = 900;
        if (!tc.win.rightPanelShown) tc.win.toggleRightPanel();
        verify(tc.win.rightPanelShown);
        waitForRendering(tc.win.contentItem);
        // The launch splash swallows input until it has faded out.
        const splash = findChild(tc.win.contentItem, "splash");
        if (splash) tryCompare(splash, "visible", false, 5000);
    }

    function cleanupTestCase() {
        if (tc.win) {
            tc.win.destroy();
            tc.win = null;
        }
        AppController.appSettingsJson = tc.savedSettings;
    }

    function stored(key) {
        try { return JSON.parse(AppController.appSettingsJson || "{}")[key]; }
        catch (e) { return undefined; }
    }

    function test_width_clamps_to_bounds() {
        tc.win.setRightPanelWidth(10000, false);
        compare(tc.win.rightPanelWidth, tc.win.rightPanelMaxWidth);
        verify(tc.win.rightPanelMaxWidth <= 720);
        tc.win.setRightPanelWidth(10, false);
        compare(tc.win.rightPanelWidth, tc.win.rightPanelMinWidth);
    }

    function test_width_persists_on_commit() {
        tc.win.setRightPanelWidth(512, true);
        compare(tc.win.rightPanelWidth, 512);
        compare(stored("rightPanelWidth"), 512);
    }

    function test_drag_handle_resizes() {
        tc.win.setRightPanelWidth(420, true);
        const handle = findChild(tc.win.contentItem, "right-panel-resize");
        verify(handle !== null, "right-panel-resize not found");
        const panel = findChild(tc.win.contentItem, "right-panel");
        tryCompare(panel, "width", 420, 2000);
        const y = handle.height / 2;
        mousePress(handle, 3, y);
        mouseMove(handle, -57, y);
        mouseRelease(handle, -57, y);
        tryCompare(panel, "width", 480, 2000);
        compare(stored("rightPanelWidth"), 480);
    }

    function test_double_click_resets() {
        tc.win.setRightPanelWidth(600, true);
        const handle = findChild(tc.win.contentItem, "right-panel-resize");
        mouseDoubleClickSequence(handle, 3, handle.height / 2);
        compare(tc.win.rightPanelWidth, tc.win.rightPanelDefaultWidth);
    }

    // Hiding the panel gives its width to the main column. The top bar
    // spanned the panel's empty column, which kept half the spare width.
    function test_hidden_panel_gives_main_column_the_room() {
        const main = findChild(tc.win.contentItem, "main-column");
        verify(main !== null);
        tc.win.toggleRightPanel();
        verify(!tc.win.rightPanelShown);
        tryVerify(function () { return main.x + main.width === tc.win.width; }, 2000,
                  "main column ends at " + (main.x + main.width) + ", window is " + tc.win.width);
        tc.win.toggleRightPanel();
        verify(tc.win.rightPanelShown);
    }

    function test_side_rail_toggle_persists() {
        const before = tc.win.sideRailExpanded;
        tc.win.toggleSideRail();
        compare(tc.win.sideRailExpanded, !before);
        compare(stored("sideRailExpanded"), !before);
        tc.win.toggleSideRail();
        compare(tc.win.sideRailExpanded, before);
    }
}
