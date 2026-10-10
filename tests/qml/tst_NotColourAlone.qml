// APP-185 (WCAG 1.4.1): a status or a priority is never told by colour
// alone. Where it is a coloured mark with no word beside it, the mark's
// shape differs per status / priority; P2 and P3, the closest colours, read
// apart by shape or text everywhere they show.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "NotColourAlone"
    when: windowShown
    visible: true
    width: 1400
    height: 900

    Item { id: host; anchors.fill: parent }

    function marksOf(root, name, out) {
        out = out || [];
        if (!root) return out;
        if (root.objectName === name && root.visible) out.push(root);
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) marksOf(kids[i], name, out);
        return out;
    }

    function test_every_builtin_status_has_its_own_shape() {
        const ids = ["backlog", "todo", "prog", "half", "review", "blocked", "done"];
        const seen = {};
        for (const id of ids) {
            const m = Theme.statusMark(id);
            verify(m.length > 0, id);
            verify(!seen[m], id + " shares its shape with " + seen[m]);
            seen[m] = id;
        }
        // A status of the user's own still has a shape, not a bare dot.
        verify(Theme.statusMark("my-own").length > 0);
        verify(!seen[Theme.statusMark("my-own")], "a custom status looks like a built-in one");
    }

    function test_every_priority_has_its_own_shape() {
        const seen = {};
        for (const p of ["P0", "P1", "P2", "P3"]) {
            const m = Theme.priorityMark(p);
            verify(!seen[m], p + " shares its shape with " + seen[m]);
            seen[m] = p;
        }
        verify(Theme.priorityMark("P2") !== Theme.priorityMark("P3"));
    }

    // The filter bar's priority chips: a shape and the name.
    function test_filter_chips_carry_the_shape() {
        const bar = createTemporaryQmlObject('import TodoCpp; FilterBar { width: 1000 }', host);
        verify(bar !== null);
        const marks = marksOf(bar, "priority-mark");
        compare(marks.length, 4);
        const texts = marks.map(m => m.text);
        compare(texts.sort().join(""), ["P0", "P1", "P2", "P3"].map(p => Theme.priorityMark(p)).sort().join(""));
    }

}
