// A colour picker: saturation/value square, hue strip, alpha strip and a hex
// field. Used by the theme editor; any "#rrggbb" / "#aarrggbb" goes in and
// comes out.
//
//   ColorPickerPopup { id: cp; onPicked: (hex) => store(hex) }
//   cp.openFor("#3bccdd", anchorItem)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp

Popup {
    id: root
    // Emitted on every change, so what the picker edits repaints live.
    signal picked(string hex)

    property real hue: 0
    property real sat: 0
    property real val: 1
    property real alpha: 1
    readonly property color current: Qt.hsva(hue, sat, val, alpha)
    readonly property string hex: _hex(current)

    padding: Theme.spXl
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: 252

    background: Rectangle {
        radius: Theme.radius
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    function _hex(c) {
        const h2 = (n) => ("0" + Math.round(n * 255).toString(16)).slice(-2);
        const rgb = h2(c.r) + h2(c.g) + h2(c.b);
        return c.a < 0.999 ? "#" + h2(c.a) + rgb : "#" + rgb;
    }

    // Load a colour without emitting: opening the picker must not write.
    function setColor(s) {
        const c = Qt.color(s);
        // Keep the hue while the colour is grey, or the strip jumps to red.
        if (c.hsvSaturation > 0 && c.hsvHue >= 0) hue = c.hsvHue;
        sat = c.hsvSaturation;
        val = c.hsvValue;
        alpha = c.a;
        hexField.text = _hex(c);
    }

    function openFor(s, anchorItem) {
        setColor(s);
        if (anchorItem) {
            const p = anchorItem.mapToItem(parent, 0, anchorItem.height + 4);
            x = p.x; y = p.y;
        }
        open();
    }

    function _emit() {
        hexField.text = hex;
        picked(hex);
    }

    contentItem: ColumnLayout {
        spacing: Theme.spLg

        RowLayout {
            spacing: Theme.spLg
            Layout.fillWidth: true

            // Saturation left → right, value bottom → top, at the chosen hue.
            Rectangle {
                id: svSquare
                objectName: "cp-sv"
                Layout.preferredWidth: 196
                Layout.preferredHeight: 150
                radius: Theme.radiusSm
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#ffffff" }
                    GradientStop { position: 1; color: Qt.hsva(root.hue, 1, 1, 1) }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSm
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#00000000" }
                        GradientStop { position: 1; color: "#ff000000" }
                    }
                }
                Rectangle {
                    width: 12; height: 12; radius: 6
                    x: root.sat * svSquare.width - 6
                    y: (1 - root.val) * svSquare.height - 6
                    color: "transparent"
                    border.color: root.val > 0.5 ? "#000000" : "#ffffff"
                    border.width: 2
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    function _at(mx, my) {
                        root.sat = Math.max(0, Math.min(1, mx / width));
                        root.val = Math.max(0, Math.min(1, 1 - my / height));
                        root._emit();
                    }
                    onPressed: (m) => _at(m.x, m.y)
                    onPositionChanged: (m) => { if (pressed) _at(m.x, m.y); }
                }
            }

            // Hue, top to bottom.
            Rectangle {
                id: hueStrip
                objectName: "cp-hue"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 150
                radius: Theme.radiusSm
                gradient: Gradient {
                    GradientStop { position: 0/6; color: "#ff0000" }
                    GradientStop { position: 1/6; color: "#ffff00" }
                    GradientStop { position: 2/6; color: "#00ff00" }
                    GradientStop { position: 3/6; color: "#00ffff" }
                    GradientStop { position: 4/6; color: "#0000ff" }
                    GradientStop { position: 5/6; color: "#ff00ff" }
                    GradientStop { position: 6/6; color: "#ff0000" }
                }
                Rectangle {
                    x: -2; width: parent.width + 4; height: 4
                    y: root.hue * hueStrip.height - 2
                    color: "transparent"
                    border.color: Theme.text; border.width: 1
                }
                MouseArea {
                    anchors.fill: parent
                    function _at(my) {
                        root.hue = Math.max(0, Math.min(0.9999, my / height));
                        root._emit();
                    }
                    onPressed: (m) => _at(m.y)
                    onPositionChanged: (m) => { if (pressed) _at(m.y); }
                }
            }
        }

        // Alpha, over a checkerboard so transparency is visible.
        Item {
            id: alphaStrip
            objectName: "cp-alpha"
            Layout.fillWidth: true
            Layout.preferredHeight: 14
            Grid {
                anchors.fill: parent
                clip: true
                columns: Math.ceil(alphaStrip.width / 7)
                Repeater {
                    model: Math.ceil(alphaStrip.width / 7) * 2
                    Rectangle {
                        required property int index
                        readonly property int cols: Math.ceil(alphaStrip.width / 7)
                        width: 7; height: 7
                        color: ((index % cols) + Math.floor(index / cols)) % 2 ? "#cccccc" : "#ffffff"
                    }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusXs
                border.color: Theme.border; border.width: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.hsva(root.hue, root.sat, root.val, 0) }
                    GradientStop { position: 1; color: Qt.hsva(root.hue, root.sat, root.val, 1) }
                }
            }
            Rectangle {
                width: 4; height: parent.height + 4; y: -2
                x: root.alpha * alphaStrip.width - 2
                color: "transparent"
                border.color: Theme.text; border.width: 1
            }
            MouseArea {
                anchors.fill: parent
                function _at(mx) {
                    root.alpha = Math.max(0, Math.min(1, mx / width));
                    root._emit();
                }
                onPressed: (m) => _at(m.x)
                onPositionChanged: (m) => { if (pressed) _at(m.x); }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spMd
            Rectangle {
                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                radius: Theme.radiusMd
                color: root.current
                border.color: Theme.border; border.width: 1
            }
            TextField {
                id: hexField
                objectName: "cp-hex"
                Layout.fillWidth: true
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsMd
                color: acceptableInput ? Theme.text : Theme.danger
                selectByMouse: true
                validator: RegularExpressionValidator { regularExpression: /#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})/ }
                background: Rectangle { radius: Theme.radiusMd; color: Theme.panel2; border.color: Theme.fieldBorder; border.width: 1 }
                onAccepted: {
                    // Emit what was typed, not the HSV round trip, which can
                    // move a channel by one.
                    const t = (text.charAt(0) === "#" ? text : "#" + text).toLowerCase();
                    root.setColor(t);
                    root.picked(t);
                }
            }
        }
    }
}
