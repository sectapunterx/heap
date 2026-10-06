// APP-184: what the pointer reveals, the keyboard reveals too. Icons that
// fade in on hover show themselves when Tab lands on them, every one of them
// has a name for a screen reader, and their tooltips open on keyboard focus
// as they do under the mouse.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "HoverKeyboard"
    when: windowShown
    visible: true
    width: 1200
    height: 800

    Item { id: host; anchors.fill: parent }

    Component {
        id: iconComp
        IconButton { glyph: "✎"; label: "Edit"; revealed: false }
    }
    Component {
        id: clickComp
        Rectangle {
            width: 22; height: 22; radius: Theme.radiusSm
            property alias area: ca
            ClickArea { id: ca; label: "Add task" }
        }
    }
    MdDocument {
        id: mdDoc
        palette: ({ "text": "#ffffff", "link": "#4488ff" })
    }
    Component {
        id: mdComp
        MdView { anchors.fill: parent; document: mdDoc }
    }
    Component {
        id: cardComp
        TaskCard { width: 360 }
    }

    function cleanup() {
        host.forceActiveFocus();
    }

    function test_icon_button_shows_and_names_itself_on_focus() {
        const b = createTemporaryObject(iconComp, host);
        verify(b !== null);
        compare(b.opacity, 0, "hidden at rest");
        compare(b.ToolTip.visible, false);
        verify(b.activeFocusOnTab, "on the Tab path while hidden");
        compare(String(b.Accessible.name), "Edit");
        b.forceActiveFocus(Qt.TabFocusReason);
        verify(b.shown);
        tryCompare(b, "opacity", 1, 1000);
        tryVerify(function () { return b.ToolTip.visible; }, 2000, "the tooltip opens on keyboard focus");
        compare(b.ToolTip.text, "Edit");
    }

    function test_click_area_tooltip_opens_on_keyboard_focus() {
        const r = createTemporaryObject(clickComp, host);
        verify(r !== null);
        const ca = r.area;
        compare(ca.ToolTip.visible, false);
        compare(String(ca.Accessible.name), "Add task");
        ca.forceActiveFocus(Qt.TabFocusReason);
        tryVerify(function () { return ca.ToolTip.visible; }, 2000, "Tab opens the tooltip");
        compare(ca.ToolTip.text, "Add task");
        host.forceActiveFocus();
        tryVerify(function () { return !ca.ToolTip.visible; }, 2000, "and leaving closes it");
    }

    // The board's column-header icons (‹ › × ⇤) fade in on hover.
    function test_column_header_icons_show_on_keyboard_focus() {
        const board = createTemporaryQmlObject('import TodoCpp; KanbanBoard { anchors.fill: parent }', host);
        verify(board !== null);
        wait(50);
        const icon = findChild(board, "column-fold");
        verify(icon !== null, "no fold icon");
        compare(icon.shown, false, "hidden at rest");
        // The ClickArea inside is the Tab stop.
        let area = null;
        for (let i = 0; i < icon.children.length; i++)
            if (icon.children[i].activeFocusOnTab !== undefined && icon.children[i].label !== undefined)
                area = icon.children[i];
        verify(area !== null);
        verify(area.activeFocusOnTab);
        verify(String(area.Accessible.name).length > 0, "named for a screen reader");
        area.forceActiveFocus(Qt.TabFocusReason);
        verify(icon.shown, "shown on keyboard focus");
        tryCompare(icon, "opacity", 1, 1000);
        tryVerify(function () { return area.ToolTip.visible; }, 2000, "its tooltip opens too");
    }

    // A code block without a language hid its Copy until the pointer came:
    // off the Tab path. Now the header folds and Tab opens it.
    function test_code_copy_is_reachable_without_the_pointer() {
        const view = createTemporaryObject(mdComp, host);
        verify(view !== null);
        const doc = mdDoc;
        doc.text = "```\nplain code\n```\n";
        doc.flush();
        let copy = null;
        tryVerify(function () { copy = findChild(view, "mdCodeCopyButton"); return copy !== null; }, 2000);
        verify(copy.activeFocusOnTab, "Copy is on the Tab path");
        compare(String(copy.Accessible.name), I18n.t("notes.code.copy"));
        const header = copy.parent.parent;
        compare(header.shown, false, "folded at rest");
        copy.forceActiveFocus(Qt.TabFocusReason);
        verify(header.shown, "Tab opens the header");
        tryCompare(header, "opacity", 1, 1000);
    }

    // The small chips' hover-only text is the card's description and its
    // tooltip on Tab.
    function test_card_chip_tooltips_reach_the_keyboard() {
        const card = cardComp.createObject(host, { task: {
            id: "github-1", title: "Fix it", priority: "P1", status: "todo",
            labels: [{ id: "a" }, { id: "b" }, { id: "c" }, { id: "d" }],
            ticket: { provider: "github", key: "#1", project: "acme/web", conflict: true }
        } });
        verify(card !== null);
        const d = card.hoverDetails;
        verify(d.indexOf("acme/web") >= 0, "the tracker: " + d);
        verify(d.indexOf(I18n.t("taskcard.conflict.tip")) >= 0, "the conflict: " + d);
        verify(d.indexOf("c, d") >= 0, "the labels past two: " + d);
        compare(String(card.Accessible.description), d);
        compare(card.ToolTip.visible, false);
        card.forceActiveFocus(Qt.TabFocusReason);
        tryVerify(function () { return card.ToolTip.visible; }, 2000, "Tab shows what hover shows");
        card.destroy();
    }

    function test_plain_card_has_no_empty_tooltip() {
        const card = cardComp.createObject(host, { task: {
            id: "T-1", title: "Local", priority: "P2", status: "todo", labels: [], ticket: ({})
        } });
        compare(card.hoverDetails, "");
        card.forceActiveFocus(Qt.TabFocusReason);
        wait(800);
        compare(card.ToolTip.visible, false);
        card.destroy();
    }
}
