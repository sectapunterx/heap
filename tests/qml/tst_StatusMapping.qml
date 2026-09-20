// Status mapping rows in the integration card.
//
// StatusMap has always taken per-user overrides and had never been given any:
// every sync called it with an empty map, so a status its built-in table does
// not recognise landed in To Do with no way to say otherwise. The C++ half is
// covered in heap_appcontroller_tests; this is the half that has to render.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "StatusMapping"
    when: windowShown
    visible: true
    width: 700
    height: 500

    Item { id: host; anchors.fill: parent }

    readonly property string provider: "gitea"

    function cleanup() {
        // The QML test profile is persistent, so a mapping left behind would
        // leak into the next run of this file.
        const rows = AppController.statusMappingFor(tc.provider);
        for (let i = 0; i < rows.length; i++)
            AppController.setStatusMapping(tc.provider, rows[i].status, "");
    }

    function test_a_mapping_round_trips_through_the_invokables() {
        AppController.setStatusMapping(tc.provider, "Needs triage", "backlog");
        const rows = AppController.statusMappingFor(tc.provider);
        let found = null;
        for (let i = 0; i < rows.length; i++)
            if (rows[i].status === "Needs triage") found = rows[i];
        verify(found !== null, "a mapped status must be offered as a row");
        compare(found.column, "backlog");
        compare(found.overridden, true);
    }

    function test_clearing_restores_the_guess() {
        AppController.setStatusMapping(tc.provider, "Needs triage", "backlog");
        // "" is what the combo's "Auto" entry sends.
        AppController.setStatusMapping(tc.provider, "Needs triage", "");
        const rows = AppController.statusMappingFor(tc.provider);
        for (let i = 0; i < rows.length; i++)
            verify(!(rows[i].status === "Needs triage" && rows[i].overridden),
                   "Auto must remove the override, not store an empty column");
    }

    // The combo is built from "Auto" plus AppController.statuses, and picks by
    // value — so every row's column must be findable in that list, or the combo
    // would show the first entry while the mapping says something else.
    function test_every_column_is_pickable_in_the_combo() {
        AppController.setStatusMapping(tc.provider, "Needs triage", "review");
        const rows = AppController.statusMappingFor(tc.provider);
        const columns = AppController.statuses.map(s => s.id);
        for (let i = 0; i < rows.length; i++)
            verify(columns.indexOf(rows[i].column) >= 0,
                   rows[i].column + " is not a column the combo offers");
    }

    function test_a_column_no_board_has_is_refused() {
        // Storing it would hide every ticket carrying that status with nothing
        // on screen to say where they went.
        AppController.setStatusMapping(tc.provider, "Bogus", "not-a-column");
        const rows = AppController.statusMappingFor(tc.provider);
        for (let i = 0; i < rows.length; i++)
            verify(rows[i].status !== "Bogus", "an unknown column must not be stored");
    }
}
