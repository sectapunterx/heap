// Storage banner, "Reset all settings" and "Start fresh" (audit PLAT-1/4/5,
// UX-5, UX-6).
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "StorageSafety"
    when: windowShown
    visible: true
    width: 900
    height: 600

    Item { id: host; anchors.fill: parent }

    property string savedSettings: ""

    function init() { savedSettings = AppController.appSettingsJson; }
    function cleanup() { AppController.appSettingsJson = savedSettings; }

    // A healthy profile shows no banner and takes no space.
    function test_banner_hidden_while_storage_is_ok() {
        compare(AppController.storageState, "ok");
        const b = createTemporaryQmlObject('import TodoCpp; StorageBanner { width: 600 }', host);
        verify(b !== null);
        compare(b.visible, false);
        compare(b.implicitHeight, 0);
    }

    // UX-5: preferences reset onto the new-install look; connections, repos,
    // own themes and layout survive; the toast's Undo puts everything back.
    function test_reset_keeps_state_and_lands_on_new_install_theme() {
        const before = {
            appearance: { darkPreset: "heap-dark", contrast: "normal", customThemes: [{ id: "mine" }] },
            notifications: { quietHours: false },
            integrations: { jira: { baseUrl: "https://jira.example" } },
            git: { watchedRepos: ["C:/src/heap"], autoMoveToInProgress: false },
            window: { x: 1, y: 2, width: 1300, height: 800, maximized: false },
            system: { closeToTray: "tray" }
        };
        AppController.appSettingsJson = JSON.stringify(before);
        const spy = createTemporaryQmlObject('import QtTest; SignalSpy { signalName: "settingsReset" }', host);
        spy.target = AppController;

        AppController.resetSettingsToDefaults();
        compare(spy.count, 1);
        const after = JSON.parse(AppController.appSettingsJson);
        compare(after.appearance.darkPreset, "heap-ink");
        compare(after.appearance.contrast, "soft");
        compare(after.appearance.customThemes.length, 1);
        compare(after.notifications, undefined);
        compare(after.integrations.jira.baseUrl, "https://jira.example");
        compare(after.git.watchedRepos[0], "C:/src/heap");
        compare(after.git.autoMoveToInProgress, undefined);
        compare(after.window.width, 1300);
        compare(after.system.closeToTray, "tray");

        AppController.undoSettingsReset();
        compare(JSON.parse(AppController.appSettingsJson).appearance.darkPreset, "heap-dark");
    }

    // UX-5: the reset row asks twice, like the rows next to it.
    function test_danger_row_needs_a_second_click() {
        const row = createTemporaryQmlObject(
            'import TodoCpp; SettingsView.DangerRow { title: "t"; buttonText: "Reset all"; width: 500 }', host);
        verify(row !== null);
        const spy = createTemporaryQmlObject('import QtTest; SignalSpy { signalName: "triggered" }', host);
        spy.target = row;
        const button = findChild(row, "danger-row-button");
        verify(button !== null);
        mouseClick(button);
        compare(spy.count, 0);
        verify(row.armed);
        mouseClick(button);
        compare(spy.count, 1);
        verify(!row.armed);
    }

    // UX-6: "Start fresh" leaves an empty Docs catalogue, not the demo one
    // re-seeded on the first visit.
    function test_start_fresh_does_not_reseed_docs() {
        const home = AppController.activeProfileId;
        const id = AppController.createProfile("Fresh probe " + Date.now());
        verify(id.length > 0);
        AppController.startFresh();
        const dv = createTemporaryQmlObject('import TodoCpp; DocsView { anchors.fill: parent }', host);
        verify(dv !== null);
        compare(dv.sections.length, 0);
        compare(dv.snippets.length, 0);
        compare(dv.contacts.length, 0);
        dv.destroy();
        AppController.activeProfileId = home;
        AppController.deleteProfile(id);
    }
}
