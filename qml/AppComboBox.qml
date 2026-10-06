pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

// The editors' drop-down field. Basic's own list was a square slab the
// width of the field with 40px rows, no outline and the current choice only
// in bold, smaller than the field's own text (VISP-2). This one opens the
// same panel an AppMenu does: rounded, outlined, compact rows, a check on
// the current choice and the focus marker on the highlighted one.
ComboBox {
    id: box
    // The field's text colour (a priority field colours its value).
    property color textColor: Theme.text
    property int textWeight: Font.Normal

    implicitHeight: 30
    font.family: Theme.fontUi
    font.pixelSize: Theme.fsMd

    background: FieldFrame { control: box }
    contentItem: Text {
        leftPadding: Theme.spLg
        rightPadding: box.indicator.width + Theme.spMd
        text: box.displayText
        textFormat: Text.PlainText
        font.family: box.font.family
        font.pixelSize: box.font.pixelSize
        font.weight: box.textWeight
        color: box.enabled ? box.textColor : Theme.textDim
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: box.width - width - Theme.spLg
        y: (box.height - height) / 2
        text: "▾"
        color: Theme.textDim
        font.pixelSize: Theme.fsMd
    }

    delegate: ItemDelegate {
        id: row
        required property var modelData
        required property int index
        objectName: "combo-row"
        width: ListView.view ? ListView.view.width : box.width
        implicitHeight: 28
        highlighted: box.highlightedIndex === row.index
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
            currentIndex: box.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThinScrollBar {}
        }
        background: Rectangle {
            radius: Theme.radiusLg
            color: Theme.panel2
            border.color: Theme.fieldBorder
            border.width: 1
            Rectangle {
                z: -1
                anchors.fill: parent
                anchors.topMargin: Theme.spXs
                anchors.bottomMargin: -Theme.spXs
                anchors.leftMargin: -1
                anchors.rightMargin: -1
                radius: parent.radius
                color: Theme.withAlpha(Theme.scrim, Theme.dark ? 0.6 : 0.18)
            }
        }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durPop; easing.type: Theme.easeEnter }
        }
    }
}
