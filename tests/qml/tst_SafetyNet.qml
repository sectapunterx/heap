// Settings → Safety net and the UI of its heads-ups (APP-157, 158, 159, 160,
// 170): every one is off until switched on, and each shows up where it says
// it will. The rules behind them are tested in C++ (test_safety_net.cpp,
// test_safety_appcontroller.cpp).
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "SafetyNet"
    when: windowShown
    visible: true
    width: 900
    height: 1400

    Item { id: host; anchors.fill: parent }

    property string savedSettings: ""
    property var madeTasks: []
    property var madePeople: []

    function init() {
        tc.savedSettings = AppController.appSettingsJson;
        AppController.appSettingsJson = "";
        tc.madeTasks = [];
        tc.madePeople = [];
    }
    function cleanup() {
        if (AppController.immersion) AppController.stopImmersion();
        for (const id of tc.madeTasks) {
            AppController.clearWaitingOn(id);
            AppController.deleteTask(id);
        }
        for (const id of tc.madePeople) AppController.deletePerson(id);
        AppController.appSettingsJson = tc.savedSettings;
    }

    function safetyOn(keys) {
        AppController.appSettingsJson = JSON.stringify({ safety: keys });
    }

    // A Person of its own, without the Docs contact newContactDraft adds.
    function makePerson(name) {
        const d = AppController.newPersonDraft();
        d.name = name;
        d.id = AppController.suggestPersonId(name);
        verify(AppController.savePerson(d));
        tc.madePeople.push(d.id);
        return d.id;
    }

    function makeTask(title, desc) {
        const d = AppController.newTaskDraft("todo");
        d.title = title;
        d.desc = desc || "";
        verify(AppController.saveTask(d));
        tc.madeTasks.push(d.id);
        return d.id;
    }

    function settingsAtSafety() {
        const sv = createTemporaryQmlObject('import TodoCpp; SettingsView { anchors.fill: parent }', host);
        verify(sv !== null);
        sv.activeSection = "safety";
        wait(50);
        return sv;
    }

    // ── The section ──

    function test_every_heads_up_is_listed_and_off() {
        const sv = settingsAtSafety();
        compare(findChild(sv, "settings-safety-empty"), null, "the placeholder is still there");
        for (const name of ["settings-safety-endOfDay", "settings-safety-waiting", "settings-safety-seenBefore",
                            "settings-safety-immersion", "settings-safety-standupDraft"]) {
            const row = findChild(sv, name);
            verify(row !== null, name + " missing");
            verify(!row.checked, name + " is on by default");
        }
        // Their parameters stay out of the way until the switch is on.
        verify(!findChild(sv, "settings-safety-endOfDayTime").visible);
        verify(!findChild(sv, "settings-safety-waitingDays").visible);
    }

    function test_a_switch_writes_settings_safety() {
        const sv = settingsAtSafety();
        findChild(sv, "settings-safety-endOfDay").toggled(true);
        verify(AppController.safety.endOfDay === true);
        tryVerify(() => findChild(sv, "settings-safety-endOfDayTime").visible);
    }

    // ── APP-158: waiting on a reply ──

    function test_the_card_and_the_editor_show_who_the_task_waits_on() {
        safetyOn({ waitingOn: true });
        const id = makeTask("safety probe waiting", "");
        AppController.setWaitingOn(id, makePerson("Safety Probe Person"));

        // The card says it waits, and how long, under the cursor; who it
        // waits on is the editor's (APP-179: a card shows no people).
        const card = createTemporaryQmlObject('import TodoCpp; TaskCard { width: 300; cursored: true }', host);
        card.task = AppController.taskById(id);
        const chip = findChild(card, "tc-waiting");
        tryVerify(() => chip.visible);
        verify(chip.text.indexOf("Safety Probe Person") < 0, chip.text);

        const te = createTemporaryQmlObject('import TodoCpp; TaskEditor { }', host);
        te.showFor(Object.assign({}, AppController.taskById(id)));
        tryVerify(() => te.opened);
        const who = findChild(te.contentItem, "te-waiting-who");
        verify(who !== null);
        verify(who.text.indexOf("Safety Probe Person") >= 0, who.text);
        te.close();
    }

    function test_nothing_shows_while_the_switch_is_off() {
        const id = makeTask("safety probe waiting off", "");
        AppController.setWaitingOn(id, makePerson("Safety Probe Off"));
        const card = createTemporaryQmlObject('import TodoCpp; TaskCard { width: 300; cursored: true }', host);
        card.task = AppController.taskById(id);
        verify(!findChild(card, "tc-waiting").visible);
    }

    // ── APP-159: seen before ──

    function test_the_hint_names_where_the_error_came_up() {
        safetyOn({ seenBefore: true });
        // A token of its own each run: the test profile outlives a run, and a
        // task left by an earlier one carrying the same error matched after
        // this run's own task was excluded.
        const token = "qml_probe_token_" + Date.now().toString(36);
        const id = makeTask("safety probe crash", "Saw KeyError: '" + token + "' in the worker after deploy.");
        const hint = createTemporaryQmlObject('import TodoCpp; SeenBeforeHint { width: 400 }', host);
        hint.text = "Traceback (most recent call last):\n  File \"w.py\", line 9\nKeyError: '" + token + "'";
        tryVerify(() => hint.shown, 3000);
        compare(hint.hit.id, id);
        verify(hint.visible);
        // The task being edited does not point at itself.
        hint.excludeTaskId = id;
        hint.refresh();
        verify(!hint.shown);
    }

    function test_the_hint_stays_quiet_when_off() {
        makeTask("safety probe crash off", "KeyError: 'qml_probe_token_off'");
        const hint = createTemporaryQmlObject('import TodoCpp; SeenBeforeHint { width: 400 }', host);
        hint.text = "KeyError: 'qml_probe_token_off'";
        hint.refresh();
        verify(!hint.shown);
    }

    // ── APP-160: focus mode ──

    function test_the_top_bar_shows_focus_mode() {
        safetyOn({ immersion: true });
        const bar = createTemporaryQmlObject('import TodoCpp; TopBar { width: 1200 }', host);
        const pill = findChild(bar, "topbar-immersion");
        verify(!pill.visible);
        AppController.startImmersion("");
        tryVerify(() => pill.visible);
        AppController.stopImmersion();
        tryVerify(() => !pill.visible);
    }

    // ── APP-170: standup draft ──

    function test_the_standup_draft_is_editable_text() {
        safetyOn({ standupDraft: true });
        makeTask("safety probe standup", "");
        const d = createTemporaryQmlObject('import TodoCpp; StandupDraftDialog { }', host);
        d.showNow();
        tryVerify(() => d.opened);
        const field = findChild(d.contentItem, "standup-draft-text");
        verify(field.text.split("\n").length >= 6, field.text);
        field.text = "edited";
        compare(field.text, "edited");
        d.close();
    }
}
