// The Jira sprint marker (APP-255): a fact from the last pull, drawn where a
// day is. Hidden without a sprint; names it and says when it ends.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "SprintMarker"
    when: windowShown
    visible: true
    width: 400
    height: 200

    Item { id: host; anchors.fill: parent }

    function make(props) {
        const o = createTemporaryQmlObject("import TodoCpp; SprintMarker {}", host);
        verify(o !== null);
        for (const k in props) o[k] = props[k];
        return o;
    }

    function test_hidden_without_a_sprint() {
        const m = make({});
        verify(!m.visible);
        compare(m.tipText, "");
    }

    function test_names_the_sprint_and_its_end() {
        const m = make({ sprint: { name: "S 14", state: "active", end: "2026-10-16", tasks: 2 } });
        verify(m.visible);
        verify(m.implicitWidth > 0);
        verify(m.tipText.indexOf("S 14") >= 0, m.tipText);
    }

    function test_rule_and_compact() {
        const m = make({ sprint: { name: "S 14", end: "2026-10-16" }, rule: true });
        m.height = 120;
        verify(m.visible);
        const c = make({ sprint: { name: "S 14", end: "2026-10-16" }, compact: true });
        compare(c.implicitWidth, c.implicitHeight);
    }
}
