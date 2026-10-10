// The day panel beside Board and List (APP-281 A2): closed by default in the
// quiet style and on a 1440 px window (six columns fit without it, APP-262),
// Ctrl \ (panel.right) opens and closes it, and the choice is remembered.
// The sort and the grouping sit beside the lens tabs (APP-262/263).
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "DayPanel"
    when: windowShown

    property var win: null
    property string savedSettings: ""

    function initTestCase() {
        tc.savedSettings = AppController.appSettingsJson;
        const s = JSON.parse(AppController.appSettingsJson || "{}");
        delete s.dayPanel;
        AppController.appSettingsJson = JSON.stringify(s);
        const comp = Qt.createComponent("qrc:/qt/qml/TodoCpp/qml/Main.qml");
        tryCompare(comp, "status", Component.Ready, 5000);
        tc.win = comp.createObject(null);
        verify(tc.win !== null);
        tc.win.width = 1440;
        tc.win.height = 900;
        tryCompare(tc.win, "width", 1440, 2000);
        wait(1200);
        AppController.currentView = "board";
    }
    function cleanupTestCase() {
        if (tc.win) tc.win.destroy();
        AppController.appSettingsJson = tc.savedSettings;
        Style.apply("bold");
    }

    function test_closed_at_1440_and_in_the_quiet_style() {
        Style.apply("bold");
        verify(!tc.win.rightPanelShown, "the day panel takes the room of the sixth column at 1440 px");
        tc.win.width = 1900;
        tryCompare(tc.win, "width", 1900, 2000);
        tryVerify(() => tc.win.rightPanelShown, 1000, "a wide window has room for it in the bold style");
        Style.apply("quiet");
        verify(!tc.win.rightPanelShown, "closed by default in the quiet style");
        tc.win.width = 1440;
        tryCompare(tc.win, "width", 1440, 2000);
        Style.apply("bold");
    }

    function test_toggle_is_remembered() {
        AppController.currentView = "list";
        verify(!tc.win.rightPanelShown);
        tc.win.runCommand("panel.right");
        verify(tc.win.rightPanelShown);
        compare(JSON.parse(AppController.appSettingsJson).dayPanel, true);
        AppController.currentView = "board";
        verify(tc.win.rightPanelShown, "the board shares the list's choice");
        tc.win.runCommand("panel.right");
        verify(!tc.win.rightPanelShown);
        compare(JSON.parse(AppController.appSettingsJson).dayPanel, false);
    }

    function test_the_lens_setting_beside_the_tabs() {
        AppController.currentView = "list";
        compare(tc.win.listGroupBy.length > 0, true);
        tc.win.setListGroupBy("status");
        compare(JSON.parse(AppController.appSettingsJson).listGroupBy, "status");
        tryVerify(() => tc.win.activeViewItem() && tc.win.activeViewItem().groupBy === "status", 1000,
                  "the list did not follow the grouping");
        tc.win.setListGroupBy("date");
        AppController.currentView = "board";
    }
}
