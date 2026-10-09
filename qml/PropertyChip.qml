import QtQuick
import TodoCpp

// "key value" chip (APP-259): a task property in the document header, a
// filter condition in the query bar, a picked option. A fixed height,
// line-height 1 and the content centred, so a row of chips lines up at any
// scale or density. Quiet keeps a thin grey outline; bold fills it
// (Theme.chipBg / chipBorder follow Style.chipFill). Activating it edits it,
// × (or Delete on it) removes it.
Item {
    id: root

    property string key: ""
    property string value: ""
    // A value that is a signal (P0, "today"): coloured in the bold style only.
    property color valueColor: Theme.text
    property bool removable: false
    property bool small: false
    // Placeholder chip ("+ property"): a dashed outline, no key.
    property bool add: false
    // A status stage ("prog", "blocked"…): its ring before the value, in the
    // bold style only (H2-Task "Статус ◑ В работе"); quiet keeps the word.
    property string ring: ""
    // A signal tint (H2-Command: "статус Заблокировано" on red): a tinted
    // fill, no outline. Transparent = the plain chip.
    property color tone: "transparent"
    readonly property bool _toned: root.tone.a > 0

    signal clicked()
    signal removed()

    implicitHeight: small ? Theme.chipHSmall : Theme.chipH
    implicitWidth: Math.min(Theme.chipMaxW, row.implicitWidth + 2 * Theme.spMd)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        visible: !root.add
        color: root._toned ? Theme.withAlpha(root.tone, area.hovered ? 0.24 : 0.16)
             : area.hovered ? Theme.surfaceCardHover : Theme.chipBg
        border.width: root._toned ? 0 : 1
        border.color: Theme.chipBorder
    }
    // "+ property": a dashed outline
    Canvas {
        id: dashed
        visible: root.add
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.setLineDash([3, 3]);
            ctx.strokeStyle = Theme.borderStrong;
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.roundedRect(0.5, 0.5, width - 1, height - 1, Theme.radiusMd, Theme.radiusMd);
            ctx.stroke();
        }
        Connections {
            target: Theme
            function onBorderStrongChanged() { dashed.requestPaint(); }
        }
    }

    ClickArea {
        id: area
        label: (root.key.length ? root.key + " " : "") + root.value
        showTip: valueText.truncated
        tip: root.value
        onActivated: root.clicked()
        Keys.onDeletePressed: if (root.removable) root.removed()
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spXs
        Text {
            visible: root.key.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.key
            color: root._toned ? Qt.tint(Theme.textMuted, Theme.withAlpha(root.tone, 0.45)) : Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: root.small ? Theme.fsXs : Theme.fsSm
        }
        StatusRing {
            visible: root.ring.length > 0 && Style.fills
            anchors.verticalCenter: parent.verticalCenter
            category: root.ring
            size: root.small ? Theme.iconSize - 2 : Theme.iconSize - 1
        }
        Text {
            id: valueText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Theme.chipMaxW - 2 * Theme.spMd
                            - (root.key.length ? keyMetrics.advanceWidth + Theme.spXs : 0)
                            - (root.ring.length > 0 && Style.fills ? Theme.iconSize + Theme.spXs : 0)
                            - (root.removable ? Theme.iconSize + Theme.spXs : 0))
            elide: Text.ElideRight
            text: root.add ? "+ " + root.value : root.value
            color: root.add ? Theme.textDim : root._toned ? Qt.tint(Theme.text, Theme.withAlpha(root.tone, 0.3)) : root.valueColor
            font.family: Theme.fontUi
            font.pixelSize: root.small ? Theme.fsXs : Theme.fsSm
            font.weight: root.add ? Theme.fwBody : Theme.fwTitle
        }
        TextMetrics {
            id: keyMetrics
            font.family: Theme.fontUi
            font.pixelSize: root.small ? Theme.fsXs : Theme.fsSm
            text: root.key
        }
        Item {
            visible: root.removable
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSize
            height: Theme.iconSize
            Icon {
                anchors.centerIn: parent
                name: "close"
                size: Theme.iconSize - 4
                color: removeArea.hovered ? Theme.text : Theme.textDim
            }
            ClickArea {
                id: removeArea
                label: I18n.t("chip.remove")
                onActivated: root.removed()
            }
        }
    }
}
