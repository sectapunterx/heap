// The query under the Tasks header (APP-261): finished clauses become chips,
// the rest stays in the field; × and Backspace take a condition back; a query
// set from outside (a saved view) is split again.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "QueryChips"
    when: windowShown
    width: 1000
    height: 200

    property var bar: null

    function typeText(t) { for (let i = 0; i < t.length; i++) keyClick(t[i]); }

    function init() {
        tc.bar = createTemporaryQmlObject('import TodoCpp; TopBar { width: 1000; section: "tasks"; view: "board" }', tc);
        verify(tc.bar !== null);
    }

    function test_a_query_from_outside_is_split_into_chips() {
        tc.bar.searchText = "status:blocked fix login priority:P0";
        compare(tc.bar.conditions.length, 2);
        compare(tc.bar.conditions[0].raw, "status:blocked");
        compare(tc.bar.conditions[1].raw, "priority:P0");
        compare(tc.bar.conditions[1].value, "P0");
    }

    function test_removing_a_chip_keeps_the_rest() {
        tc.bar.searchText = "due:week fix tag:ui";
        tc.bar.removeCondition(0);
        compare(tc.bar.searchText, "tag:ui fix");
        compare(tc.bar.conditions.length, 1);
    }

    function test_a_typed_clause_moves_into_a_chip() {
        tc.bar.focusSearch();
        typeText("is:blocked ");
        tryCompare(tc.bar, "searchText", "is:blocked");
        compare(tc.bar.conditions.length, 1);
        typeText("api");
        tryCompare(tc.bar, "searchText", "is:blocked api");
    }

    function test_backspace_on_an_empty_field_takes_the_last_chip() {
        tc.bar.searchText = "is:blocked due:today";
        tc.bar.focusEnd();
        keyClick(Qt.Key_Backspace);
        compare(tc.bar.searchText, "is:blocked");
    }

    function test_an_or_query_stays_as_typed() {
        tc.bar.searchText = "status:todo OR status:blocked";
        compare(tc.bar.conditions.length, 0);
    }

    function test_an_unknown_clause_is_marked_not_dropped() {
        tc.bar.searchText = "stauts:x";
        compare(tc.bar.conditions.length, 1);
        verify(tc.bar.conditions[0].bad);
    }

    function test_clear_resets_everything() {
        tc.bar.searchText = "is:blocked words";
        tc.bar.clearQuery();
        compare(tc.bar.searchText, "");
        compare(tc.bar.conditions.length, 0);
    }
}
