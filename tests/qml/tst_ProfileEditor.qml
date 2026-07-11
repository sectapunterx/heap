// ProfileEditor popup: smoke-load, the showCreate/showRename/showDuplicate
// mode contract, and the AppController profile wiring its Save button relies
// on (createProfile activates the new profile; duplicateProfile activates the
// copy so setProfileColor(activeProfileId) recolors the right one).
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ProfileEditor"
    when: windowShown
    visible: true
    width: 500
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // The qttest profile persists between runs and is shared by all tst files,
    // so drop any probe profiles a previous (possibly failed) run left behind.
    function cleanupProbes() {
        const profs = AppController.profiles;
        for (let i = 0; i < profs.length; i++) {
            if (String(profs[i].name).indexOf("pe-probe") === 0
                    && AppController.profiles.length > 1)
                AppController.deleteProfile(String(profs[i].id));
        }
    }

    // Smoke: the popup instantiates standalone and exposes its defaults.
    function test_smoke_load() {
        const pe = make('import TodoCpp; ProfileEditor { }');
        compare(pe.mode, "create");
        compare(pe.profileId, "");
        compare(pe.presetName, "");
        compare(pe.presetColor, "");
        verify(!pe.visible, "popup must start closed");
        // Save picks colors out of this array — pin its shape.
        compare(pe.palette.length, 8);
        compare(String(pe.palette[0]).toLowerCase(), "#5cc2dd");
    }

    // showCreate() resets stale rename state back to create mode and opens.
    function test_show_create_resets_mode() {
        const pe = make('import TodoCpp; ProfileEditor { }');
        pe.mode = "rename";
        pe.profileId = "prof-stale";
        pe.showCreate();
        compare(pe.mode, "create");
        compare(pe.profileId, "");
        tryCompare(pe, "opened", true);
        pe.close();
        tryCompare(pe, "opened", false);
    }

    // showRename(id, name, color) arms rename mode for the given profile.
    function test_show_rename_presets() {
        const pe = make('import TodoCpp; ProfileEditor { }');
        pe.showRename("prof-abc", "My profile", pe.palette[3]);
        compare(pe.mode, "rename");
        compare(pe.profileId, "prof-abc");
        tryCompare(pe, "opened", true);
        pe.close();
        tryCompare(pe, "opened", false);
    }

    // showDuplicate(id, sourceName, sourceColor) arms duplicate mode.
    function test_show_duplicate_presets() {
        const pe = make('import TodoCpp; ProfileEditor { }');
        pe.showDuplicate("prof-src", "Alpha", "");
        compare(pe.mode, "duplicate");
        compare(pe.profileId, "prof-src");
        tryCompare(pe, "opened", true);
        pe.close();
        tryCompare(pe, "opened", false);
    }

    // The create/rename branch of saveBtn.activate(): createProfile must
    // return the new id and activate it (the dialog closes into the new
    // profile), and renameProfile/setProfileColor must land on that profile.
    function test_save_wiring_create_rename_recolor() {
        cleanupProbes();
        const prevActive = AppController.activeProfileId;
        const before = AppController.profiles.length;

        const id = AppController.createProfile("pe-probe-create", "#5cc2dd");
        verify(id !== "", "createProfile must return the new profile id");
        compare(AppController.profiles.length, before + 1);
        compare(AppController.activeProfileId, id,
                "createProfile must activate the new profile");

        AppController.renameProfile(id, "pe-probe-renamed");
        AppController.setProfileColor(id, "#6cc4b8");
        const m = AppController.profileById(id);
        compare(String(m.name), "pe-probe-renamed");
        compare(String(m.color).toLowerCase(), "#6cc4b8");

        // Restore shared state: drop the probe, reactivate the old profile.
        AppController.deleteProfile(id);
        compare(AppController.profiles.length, before);
        AppController.activeProfileId = prevActive;
        compare(AppController.activeProfileId, prevActive);
    }

    // The duplicate branch of saveBtn.activate() recolors via
    // AppController.activeProfileId right after duplicateProfile — this only
    // works if duplicateProfile activates the copy. Pin that assumption.
    function test_save_wiring_duplicate_activates_copy() {
        cleanupProbes();
        const prevActive = AppController.activeProfileId;
        const before = AppController.profiles.length;

        const srcId = AppController.createProfile("pe-probe-src", "#7cc492");
        verify(srcId !== "");
        const dupId = AppController.duplicateProfile(srcId, "pe-probe-dup");
        verify(dupId !== "", "duplicateProfile must return the copy's id");
        verify(dupId !== srcId, "the copy must get a fresh id");
        compare(AppController.activeProfileId, dupId,
                "duplicateProfile must activate the copy");

        // Recolor through activeProfileId exactly like the editor does:
        // the copy changes, the source keeps its color.
        AppController.setProfileColor(AppController.activeProfileId, "#e6984c");
        compare(String(AppController.profileById(dupId).color).toLowerCase(), "#e6984c");
        compare(String(AppController.profileById(srcId).color).toLowerCase(), "#7cc492");

        // Restore shared state.
        AppController.deleteProfile(dupId);
        AppController.deleteProfile(srcId);
        compare(AppController.profiles.length, before);
        AppController.activeProfileId = prevActive;
        compare(AppController.activeProfileId, prevActive);
    }
}
