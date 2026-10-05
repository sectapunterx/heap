// The board's sort menu (FilterBar): APP-117 added an ID sort and a reverse
// toggle. Reversing is a "-desc" suffix on the mode, so saved views and the
// stored filters carry it without a field of their own; manual has no reverse.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "FilterBarSort"
    when: windowShown
    visible: true
    width: 1000
    height: 200

    Item { id: host; anchors.fill: parent }

    function make(mode) {
        const bar = createTemporaryQmlObject('import TodoCpp; FilterBar { width: 1000; showSort: true }', host);
        verify(bar !== null);
        bar.sortMode = mode;
        bar.sortModeRequested.connect(function (m) { bar.sortMode = m; });
        return bar;
    }

    function test_reverse_flips_the_direction_and_back() {
        const bar = make("priority");
        const rev = findChild(bar, "sort-reverse");
        verify(rev !== null);
        verify(rev.enabled);
        verify(!rev.checked);
        rev.triggered();
        compare(bar.sortMode, "priority-desc");
        verify(rev.checked);
        rev.triggered();
        compare(bar.sortMode, "priority");
    }

    function test_picking_a_mode_keeps_the_direction() {
        const bar = make("due-desc");
        findChild(bar, "sort-title").triggered();
        compare(bar.sortMode, "title-desc");
        findChild(bar, "sort-manual").triggered();
        compare(bar.sortMode, "manual");
    }

    function test_manual_cannot_be_reversed() {
        const bar = make("manual");
        verify(!findChild(bar, "sort-reverse").enabled);
    }

    function test_the_button_says_reversed() {
        const bar = make("id-desc");
        const btn = findChild(bar, "sort-button");
        compare(btn.label, I18n.t("filter.sort.id") + " ↓");
    }
}
