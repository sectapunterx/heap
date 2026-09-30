// Tracker conflicts and filter changes, as the user sees them (audit INT-1,
// INT-4). A card both sides edited carries a conflict marker; the editor shows
// the tracker's version with "Use tracker version" / "Keep mine". A card left
// behind by a filter change says so quietly instead of "not in tracker".
//
// Driven with hand-built task objects, so nothing here syncs.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TrackerConflict"
    when: windowShown
    visible: true
    width: 520
    height: 700

    Item { id: host; anchors.fill: parent }

    Component {
        id: cardComp
        TaskCard { width: 360 }
    }

    function ticketTask(extra) {
        const t = {
            id: "github-77",
            title: "mine",
            desc: "local body",
            priority: "P1",
            status: "todo",
            labels: [],
            _isNew: false,
            ticket: {
                provider: "github",
                key: "#77",
                url: "https://github.com/acme/web/issues/77",
                conflict: true,
                conflicts: ["title", "priority"],
                remoteTitle: "theirs",
                remoteBody: "tracker body",
                remotePriority: "P3"
            }
        };
        for (const k in (extra || {})) t.ticket[k] = extra[k];
        return t;
    }

    function test_card_shows_a_conflict_marker() {
        const card = cardComp.createObject(host, { task: ticketTask() });
        verify(card !== null);
        const chip = findChild(card, "tc-conflict");
        verify(chip !== null, "no conflict marker on the card");
        verify(chip.visible, "a conflicting card looks in sync");
        card.destroy();
    }

    function test_out_of_scope_card_is_not_called_gone() {
        const card = cardComp.createObject(host, { task: ticketTask({ conflict: false, outOfScope: true, gone: false }) });
        verify(findChild(card, "tc-out-of-scope").visible, "an out-of-scope card has no marker");
        verify(!findChild(card, "tc-sync-state").visible, "an out-of-scope card reads as gone/unsynced");
        verify(!findChild(card, "tc-conflict").visible);
        card.destroy();
    }

    function test_editor_offers_the_tracker_version() {
        const te = createTemporaryQmlObject('import TodoCpp; TaskEditor { }', host);
        te.showFor(ticketTask());
        const panel = findChild(te, "te-ticket-conflict");
        verify(panel !== null, "no conflict panel in the editor");
        verify(panel.visible, "the editor hides the conflict");
        compare(te._conflictRows.length, 2);
        compare(te._conflictRows[0].value, "theirs");
        compare(te._conflictRows[1].value, "P3");

        findChild(te, "te-conflict-use-tracker").clicked();
        verify(!panel.visible, "the panel stayed after picking a side");
    }

    function test_use_tracker_version_fills_the_fields() {
        const te = createTemporaryQmlObject('import TodoCpp; TaskEditor { }', host);
        te.showFor(ticketTask());
        te._takeTrackerVersion();
        // The title field is the first TextField holding the draft title.
        let found = false;
        const walk = (item) => {
            if (!item || found) return;
            if (item.text === "theirs" && item.placeholderText !== undefined) found = true;
            for (let i = 0; i < (item.children ? item.children.length : 0); ++i) walk(item.children[i]);
            if (item.contentItem) walk(item.contentItem);
        };
        walk(te.contentItem || te);
        verify(found, "the tracker's title did not reach the title field");
    }

    function test_keep_mine_hides_the_panel_and_keeps_fields() {
        const te = createTemporaryQmlObject('import TodoCpp; TaskEditor { }', host);
        te.showFor(ticketTask());
        findChild(te, "te-conflict-keep-mine").clicked();
        verify(!findChild(te, "te-ticket-conflict").visible);
        compare(te._conflictResolved, true);
        // A fresh open of another card starts unresolved again.
        te.showFor(ticketTask());
        verify(findChild(te, "te-ticket-conflict").visible);
    }

    function test_no_panel_without_a_conflict() {
        const te = createTemporaryQmlObject('import TodoCpp; TaskEditor { }', host);
        te.showFor(ticketTask({ conflict: false, conflicts: [] }));
        verify(!findChild(te, "te-ticket-conflict").visible);
    }
}
