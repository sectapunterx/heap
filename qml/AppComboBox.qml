pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import TodoCpp
import "KeyRules.js" as KeyRules

// The editors' drop-down field. Basic's own list was a square slab the
// width of the field with 40px rows, no outline and the current choice only
// in bold, smaller than the field's own text (VISP-2). This one opens the
// same panel an AppMenu does: rounded, outlined, compact rows, a check on
// the current choice and the focus marker on the highlighted one.
ComboBox {
    id: box
    // The field's text colour (a priority field colours its value).
    property color textColor: Theme.text
    property int textWeight: Theme.fwBody
    // A stage ring before the value (a column picked for a tracker status,
    // sheet N/X-Set-Trackers, R3-127). Empty = none.
    property string ring: ""
    // A pill as wide as its value with a small caret, not a field.
    property bool compact: false

    implicitHeight: box.compact ? Theme.chipH : 30
    font.family: Theme.fontUi

    // Type to find (APP-279): "гот" picks "Готово". The letters open the
    // list on the first row that starts so (or has a word that does); Enter
    // takes it, as it takes a row reached with the arrows. A pause of a
    // second starts the search over.
    property string _typed: ""
    property real _typedAt: 0
    property int typedIndex: -1
    onHighlightedIndexChanged: box.typedIndex = -1
    Connections {
        target: box.popup
        function onClosed() { box.typedIndex = -1; box._typed = ""; }
    }
    function typeAhead(text) {
        const now = Date.now();
        const fresh = now - box._typedAt > 1000;
        box._typed = KeyRules.typeAheadBuffer(box._typed, text, now, box._typedAt, 1000);
        box._typedAt = now;
        const labels = [];
        for (let i = 0; i < box.count; i++) labels.push(box.textAt(i));
        const cur = box.typedIndex >= 0 ? box.typedIndex : (box.popup.visible ? box.highlightedIndex : box.currentIndex);
        const from = fresh && box._typed.length === 1 ? cur + 1 : Math.max(0, cur);
        const hit = KeyRules.typeAheadMatch(labels, box._typed, Math.max(0, from) % Math.max(1, box.count));
        if (hit < 0) return;
        if (!box.popup.visible) box.popup.open();
        box.typedIndex = hit;
    }
    Keys.onPressed: (event) => {
        if (box.editable || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return;
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
        if (enter && box.popup.visible && box.typedIndex >= 0) {
            const i = box.typedIndex;
            box.popup.close();
            box.currentIndex = i;
            box.activated(i);
            event.accepted = true;
            return;
        }
        const t = event.text;
        if (!t || t.length !== 1 || t.charCodeAt(0) <= 32 || t.charCodeAt(0) === 127) return;
        box.typeAhead(t);
        event.accepted = true;
    }
    font.pixelSize: Theme.fsMd

    background: FieldFrame { control: box }
    contentItem: Item {
        readonly property real _lead: box.compact ? Theme.spMd : Theme.spLg
        implicitWidth: valueText.x + valueText.implicitWidth + box.indicator.width + Theme.spMd
        implicitHeight: valueText.implicitHeight
        StatusRing {
            id: ringMark
            visible: box.ring.length > 0
            x: parent._lead
            anchors.verticalCenter: parent.verticalCenter
            category: box.ring.length > 0 ? box.ring : "todo"
        }
        Text {
            id: valueText
            x: ringMark.visible ? ringMark.x + ringMark.width + Theme.spSm : parent._lead
            width: Math.max(0, parent.width - x - box.indicator.width - Theme.spMd)
            height: parent.height
            text: box.displayText
            textFormat: Text.PlainText
            font.family: box.font.family
            font.pixelSize: box.font.pixelSize
            font.weight: box.textWeight
            color: box.enabled ? box.textColor : Theme.textDim
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
    indicator: Text {
        x: box.width - width - (box.compact ? Theme.spMd : Theme.spLg)
        y: (box.height - height) / 2
        text: "▾"
        color: Theme.textDim
        font.pixelSize: box.compact ? Theme.fsXs : Theme.fsMd
    }

    delegate: ItemDelegate {
        id: row
        required property var modelData
        required property int index
        objectName: "combo-row"
        width: ListView.view ? ListView.view.width : box.width
        implicitHeight: 28
        highlighted: (box.typedIndex >= 0 ? box.typedIndex : box.highlightedIndex) === row.index
        leftPadding: Theme.spLg
        rightPadding: Theme.spLg
        readonly property bool current: box.currentIndex === row.index
        readonly property string label: {
            const m = row.modelData;
            if (box.textRole && m && typeof m === "object") return String(m[box.textRole] ?? "");
            return String(m ?? "");
        }
        contentItem: Row {
            spacing: Theme.spMd
            Text {
                width: Theme.fsMd
                anchors.verticalCenter: parent.verticalCenter
                text: row.current ? "✓" : ""
                color: Theme.accentStrong
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: row.availableWidth - Theme.fsMd - Theme.spMd
                anchors.verticalCenter: parent.verticalCenter
                text: row.label
                textFormat: Text.PlainText
                color: row.current ? Theme.accentStrong : Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                elide: Text.ElideRight
            }
        }
        background: Rectangle {
            radius: Theme.radiusSm
            color: row.highlighted || row.down ? Theme.rowHighlight : "transparent"
            Rectangle {
                visible: row.highlighted
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: parent.height - 2 * Theme.spXs
                radius: Theme.radiusXs
                color: Theme.focusRing
            }
        }
    }

    popup: Popup {
        objectName: "combo-popup"
        y: box.height + Theme.sp2xs
        width: Math.max(box.width, 160)
        padding: Theme.spXs
        // Kept inside the window: a long list flips or shortens instead of
        // running off its bottom edge.
        margins: Theme.spMd
        implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, 320)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: box.popup.visible ? box.delegateModel : null
            currentIndex: box.typedIndex >= 0 ? box.typedIndex : box.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThinScrollBar {}
        }
        background: PopupSurface {}
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durPop; easing.type: Theme.easeEnter }
        }
    }
}
