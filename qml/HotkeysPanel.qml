// Hotkey catalog: lists every rebindable action and lets the user capture
// a new sequence inline. Mirrors the TweaksPanel popup pattern.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: false
    focus: true
    padding: 0
    width: 460
    height: Math.min(580, Math.max(360, headerArea.height + listArea.contentHeight + footerArea.height + 8))
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    // Tracks how many chip capture sessions are active (usually 0 or 1).
    // While > 0, Main.qml disables every global Shortcut so the captured
    // combination doesn't accidentally trigger its current owner.
    property int _activeCaptures: 0
    readonly property bool isCapturing: _activeCaptures > 0

    onClosed: _activeCaptures = 0

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    function _labelFor(actionId) {
        if (!actionId) return "";
        return AppController.shortcutLabel(actionId);
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── Header ────────────────────────────────────────────
        Item {
            id: headerArea
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 8
                spacing: 8
                Text {
                    text: "HOTKEYS"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    radius: 5; height: 22; implicitWidth: resetAllT.implicitWidth + 14
                    color: resetAllMA.containsMouse ? Theme.panel3 : "transparent"
                    border.color: Theme.border; border.width: 1
                    Text { id: resetAllT; anchors.centerIn: parent
                        text: I18n.t("hotkeys.allClear"); color: Theme.textMuted; font.pixelSize: 11
                    }
                    MouseArea {
                        id: resetAllMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AppController.resetAllShortcuts()
                    }
                }
                Rectangle {
                    width: 22; height: 22; radius: 5
                    color: closeMA.containsMouse ? Theme.panel3 : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"; color: Theme.textDim; font.pixelSize: 12 }
                    MouseArea {
                        id: closeMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        // ── List of bindings ─────────────────────────────────
        ListView {
            id: listArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: AppController.shortcuts
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            delegate: BindingRow {
                required property var modelData
                width: ListView.view.width
                actionId:        modelData.id
                actionLabel:     modelData.label
                actionDescription: modelData.description
                sequence:        modelData.sequence
                defaultSequence: modelData.defaultSequence
            }
        }

        // ── Footer ────────────────────────────────────────────
        Rectangle {
            id: footerArea
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: Theme.panel2
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: Theme.border }
            Text {
                anchors.centerIn: parent
                text: I18n.t("hotkeys.recordHelp")
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
        }
    }

    // ── Inline components ────────────────────────────────────

    component BindingRow: Rectangle {
        id: row
        property string actionId: ""
        property string actionLabel: ""
        property string actionDescription: ""
        property string sequence: ""
        property string defaultSequence: ""

        height: 60
        color: rowHover.containsMouse ? Theme.panel2 : "transparent"

        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 1; color: Theme.border
        }

        MouseArea { id: rowHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14; anchors.rightMargin: 12
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: row.actionLabel
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: row.actionDescription
                    color: Theme.textMuted
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            KeyCaptureChip {
                actionId:        row.actionId
                sequence:        row.sequence
                defaultSequence: row.defaultSequence
            }
        }
    }

    component KeyCaptureChip: Item {
        id: chip
        property string actionId: ""
        property string sequence: ""
        property string defaultSequence: ""

        property bool   capturing: false
        property string candidate: ""
        property string conflictName: ""

        implicitWidth: 188
        implicitHeight: 46

        function _isPureModifier(k) {
            return k === Qt.Key_Control || k === Qt.Key_Shift
                || k === Qt.Key_Alt     || k === Qt.Key_Meta
                || k === Qt.Key_AltGr;
        }

        function _namedKey(k) {
            // Qt::Key codes for keys that have no printable ev.text.
            switch (k) {
                case Qt.Key_Space:      return "Space";
                case Qt.Key_Tab:        return "Tab";
                case Qt.Key_Backtab:    return "Backtab";
                case Qt.Key_Return:     return "Return";
                case Qt.Key_Enter:      return "Enter";
                case Qt.Key_Escape:     return "Escape";
                case Qt.Key_Backspace:  return "Backspace";
                case Qt.Key_Delete:     return "Delete";
                case Qt.Key_Insert:     return "Insert";
                case Qt.Key_Home:       return "Home";
                case Qt.Key_End:        return "End";
                case Qt.Key_PageUp:     return "PgUp";
                case Qt.Key_PageDown:   return "PgDown";
                case Qt.Key_Left:       return "Left";
                case Qt.Key_Right:      return "Right";
                case Qt.Key_Up:         return "Up";
                case Qt.Key_Down:       return "Down";
                case Qt.Key_F1:         return "F1";
                case Qt.Key_F2:         return "F2";
                case Qt.Key_F3:         return "F3";
                case Qt.Key_F4:         return "F4";
                case Qt.Key_F5:         return "F5";
                case Qt.Key_F6:         return "F6";
                case Qt.Key_F7:         return "F7";
                case Qt.Key_F8:         return "F8";
                case Qt.Key_F9:         return "F9";
                case Qt.Key_F10:        return "F10";
                case Qt.Key_F11:        return "F11";
                case Qt.Key_F12:        return "F12";
            }
            return "";
        }

        function _buildSequenceString(ev) {
            const mods = [];
            if (ev.modifiers & Qt.ControlModifier) mods.push("Ctrl");
            if (ev.modifiers & Qt.AltModifier)     mods.push("Alt");
            if (ev.modifiers & Qt.ShiftModifier)   mods.push("Shift");
            // Win/Linux only — Meta (Win/Super) ignored on purpose.

            let key = "";
            // Letters / digits — derive directly from Qt.Key code so the
            // sequence is stable even when text is empty (Ctrl+Shift+letter
            // typically yields no printable ev.text on Linux/X11).
            if (ev.key >= Qt.Key_A && ev.key <= Qt.Key_Z) {
                key = String.fromCharCode(ev.key);
            } else if (ev.key >= Qt.Key_0 && ev.key <= Qt.Key_9) {
                key = String.fromCharCode(ev.key);
            } else if (ev.text && ev.text.length > 0 && ev.text.charCodeAt(0) >= 32) {
                key = ev.text;
                if (key.length === 1 && key.toLowerCase() !== key.toUpperCase())
                    key = key.toUpperCase();
            } else {
                key = _namedKey(ev.key);
            }
            if (!key || key.length === 0) return "";
            return mods.concat([key]).join("+");
        }

        function startCapture() {
            if (capturing) return;
            capturing = true;
            candidate = sequence;
            conflictName = "";
            root._activeCaptures++;
            captureField.forceActiveFocus();
        }
        function cancelCapture() {
            if (!capturing) return;
            capturing = false; candidate = ""; conflictName = "";
            root._activeCaptures = Math.max(0, root._activeCaptures - 1);
        }
        function commit() {
            AppController.setShortcut(actionId, candidate);
            cancelCapture();
        }

        RowLayout {
            anchors.fill: parent
            spacing: 4

            // ── chip (or capture field) ──────────────────
            Rectangle {
                id: chipBox
                Layout.fillWidth: true
                height: 26
                radius: 6
                color: chip.capturing ? Theme.accentSoft : Theme.panel2
                border.color: chip.capturing
                    ? Theme.accent
                    : (chip.conflictName.length > 0 ? Theme.p0 : Theme.border)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: chip.capturing
                        ? (chip.candidate.length > 0 ? chip.candidate : I18n.t("hotkeys.recordPress"))
                        : (chip.sequence.length > 0 ? chip.sequence : I18n.t("common.notSet"))
                    color: chip.capturing
                        ? (chip.candidate.length > 0 ? Theme.text : Theme.textDim)
                        : (chip.sequence.length > 0 ? Theme.text : Theme.textDim)
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }

                // Invisible focus receiver for Keys.onPressed during capture.
                Item {
                    id: captureField
                    anchors.fill: parent
                    focus: chip.capturing
                    activeFocusOnTab: true
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            chip.cancelCapture();
                            event.accepted = true; return;
                        }
                        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                            chip.candidate = "";
                            chip.conflictName = "";
                            event.accepted = true; return;
                        }
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (chip.candidate.length > 0 || chip.sequence.length > 0)
                                chip.commit();
                            event.accepted = true; return;
                        }
                        if (chip._isPureModifier(event.key)) {
                            event.accepted = true; return;
                        }
                        const seq = chip._buildSequenceString(event);
                        if (seq.length > 0) {
                            chip.candidate = seq;
                            const conflictId = AppController.findShortcutConflict(chip.actionId, seq);
                            chip.conflictName = conflictId.length > 0
                                ? AppController.shortcutLabel(conflictId)
                                : "";
                            // Auto-commit if no modifier-free single-letter; otherwise wait for Enter.
                        }
                        event.accepted = true;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chip.capturing ? chip.commit() : chip.startCapture()
                }
            }

            Rectangle {
                width: 22; height: 22; radius: 4
                color: editMA.containsMouse ? Theme.panel3 : "transparent"
                border.color: Theme.border; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: chip.capturing ? "✓" : "✎"
                    color: chip.capturing ? Theme.accentStrong : Theme.textMuted
                    font.pixelSize: 11
                }
                MouseArea {
                    id: editMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chip.capturing ? chip.commit() : chip.startCapture()
                }
            }

            Rectangle {
                width: 22; height: 22; radius: 4
                visible: chip.sequence !== chip.defaultSequence
                color: resetMA.containsMouse ? Theme.panel3 : "transparent"
                border.color: Theme.border; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "↺"; color: Theme.textMuted; font.pixelSize: 11
                }
                MouseArea {
                    id: resetMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { AppController.resetShortcut(chip.actionId); chip.cancelCapture(); }
                }
            }
        }

        // Conflict warning below the chip (only when capturing).
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -2
            visible: chip.capturing && chip.conflictName.length > 0
            text: I18n.t("hotkeys.conflict.body").arg(chip.conflictName)
            color: Theme.p0
            font.pixelSize: 9
            elide: Text.ElideRight
            width: parent.width
        }
    }

    // Dimmed backdrop is *not* used here — the panel is non-modal (mirrors Tweaks)
    // so the user can interact with the app while watching shortcuts.
}
