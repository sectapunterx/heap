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
    // Re-parented to the rail button by Main._togglePopover — see TweaksPanel.
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    // The action whose chip is recording, "" when none. While one is, Main.qml
    // disables every global Shortcut so the captured combination doesn't
    // trigger its current owner.
    //
    // Held here, not on the chip: committing a binding rewrites
    // AppController.shortcuts, the list rebuilds its delegates, and the chip
    // that was recording is destroyed mid-handler. A per-chip counter was then
    // never decremented ("cancelCapture is not a function") and every global
    // shortcut stayed dead until the panel closed.
    property string capturingId: ""
    readonly property bool isCapturing: capturingId.length > 0

    onClosed: { capturingId = ""; resetAllArmed = false; }
    // Keyboard in: the first binding takes focus, so Tab / arrows walk the
    // list and Enter or Space starts recording on the focused one.
    onOpened: Qt.callLater(function () {
        if (listArea.count > 0) {
            listArea.currentIndex = 0;
            listArea.forceActiveFocus();
        }
    })

    // "↺ all" wipes every custom binding. The first press arms it, the
    // second (within 4 s) resets — the same two-step as Start fresh.
    property bool resetAllArmed: false
    function _pressResetAll() {
        if (!resetAllArmed) {
            resetAllArmed = true;
            resetAllDisarm.restart();
            return;
        }
        resetAllArmed = false;
        resetAllDisarm.stop();
        capturingId = "";
        AppController.resetAllShortcuts();
    }
    Timer { id: resetAllDisarm; interval: 4000; onTriggered: root.resetAllArmed = false }

    background: PopupSurface {}

    // The cheat-sheet reads by area (APP-166): what works everywhere, then
    // views, the board, the calendar, notes and profiles. The catalogue keeps
    // its own order inside each group.
    readonly property var groupOrder: ["general", "views", "board", "calendar", "notes", "profiles"]
    function groupOf(actionId) {
        const id = String(actionId);
        if (id.indexOf("view.") === 0 || id.indexOf("savedView.") === 0 || id.indexOf("zoom.") === 0
                || id.indexOf("section.") === 0 || id.indexOf("nav.") === 0) return "views";
        if (id.indexOf("board.") === 0 || id.indexOf("selection.") === 0 || id.indexOf("task.") === 0
                || id.indexOf("cursor.") === 0) return "board";
        if (id.indexOf("cal.") === 0) return "calendar";
        if (id.indexOf("notes.") === 0) return "notes";
        if (id.indexOf("profile.") === 0 || id === "person.new") return "profiles";
        return "general";
    }
    // The catalogue, grouped; the first row of a group carries its heading.
    readonly property var rows: {
        const list = AppController.shortcuts;
        const out = [];
        for (let g = 0; g < groupOrder.length; g++) {
            let first = true;
            for (let i = 0; i < list.length; i++) {
                if (groupOf(list[i].id) !== groupOrder[g]) continue;
                out.push(Object.assign({ group: groupOrder[g], first: first }, list[i]));
                first = false;
            }
        }
        return out;
    }

    // After a commit the list is rebuilt; put the keyboard back on the row
    // that was just bound so the next Tab continues from there.
    // Scrolls the list to the row of `actionId`; its index, or -1.
    function revealRow(actionId) {
        const list = root.rows;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id !== actionId) continue;
            listArea.positionViewAtIndex(i, ListView.Contain);
            return i;
        }
        return -1;
    }

    function _refocusRow(actionId) {
        const list = root.rows;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id !== actionId) continue;
            listArea.currentIndex = i;
            listArea.positionViewAtIndex(i, ListView.Contain);
            const row = listArea.itemAtIndex(i);
            if (row && row.focusChip) row.focusChip();
            return;
        }
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
                anchors.leftMargin: Theme.sp2xl; anchors.rightMargin: Theme.spMd
                spacing: Theme.spMd
                Text {
                    text: I18n.t("hotkeys.editTitle")
                    color: Theme.textDim
                    font.pixelSize: Theme.fsSm
                    font.weight: Theme.fwTitle
                }
                // `?` opens this list from anywhere outside a text field.
                Text {
                    objectName: "hotkeys-question-hint"
                    text: I18n.t("hotkeys.questionHint")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsXs
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    id: resetAllBtn
                    objectName: "hotkeys-reset-all"
                    radius: Theme.radiusSm; height: 22; implicitWidth: resetAllT.implicitWidth + 14
                    color: root.resetAllArmed ? Theme.withAlpha(Theme.danger, 0.12)
                         : resetAllMA.containsMouse ? Theme.panel3 : "transparent"
                    border.color: resetAllBtn.activeFocus ? Theme.focusRing
                                : root.resetAllArmed ? Theme.danger : Theme.border
                    border.width: resetAllBtn.activeFocus ? 2 : 1
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: resetAllT.text
                    Keys.onSpacePressed: root._pressResetAll()
                    Keys.onReturnPressed: root._pressResetAll()
                    Keys.onEnterPressed: root._pressResetAll()
                    Text { id: resetAllT; anchors.centerIn: parent
                        text: root.resetAllArmed ? I18n.t("hotkeys.allClear.confirm") : I18n.t("hotkeys.allClear")
                        color: root.resetAllArmed ? Theme.danger : Theme.textMuted
                        font.pixelSize: Theme.fsSm
                    }
                    MouseArea {
                        id: resetAllMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._pressResetAll()
                    }
                }
                Rectangle {
                    width: 22; height: 22; radius: Theme.radiusSm
                    color: closeMA.hovered ? Theme.panel3 : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"; color: Theme.textDim; font.pixelSize: Theme.fsMd }
                    ClickArea {
                        id: closeMA
                        objectName: "hotkeys-close"
                        label: I18n.t("common.close")
                        shortcutId: "hotkeys.open"
                        onActivated: root.close()
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        // ── List of bindings ─────────────────────────────────
        ListView {
            id: listArea
            Accessible.role: Accessible.List
            Accessible.name: I18n.t("hotkeys.title")
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.rows
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            // Tab into the list lands on the current row's chip; Up/Down move
            // between rows.
            activeFocusOnTab: true
            keyNavigationEnabled: true
            delegate: BindingRow {
                required property var modelData
                width: ListView.view.width
                actionId:        modelData.id
                group:           modelData.first ? modelData.group : ""
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
                font.family: Theme.fontUi
                font.features: Theme.tabularNums
                font.pixelSize: Theme.fsXs
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
        // Set on the first row of a group: its heading is drawn above it.
        property string group: ""
        readonly property int _headH: row.group.length > 0 ? 30 : 0

        height: 60 + row._headH
        color: "transparent"
        Rectangle {
            anchors.fill: rowBody
            color: rowHover.containsMouse ? Theme.panel2 : "transparent"
        }
        Rectangle {
            id: groupHead
            visible: row.group.length > 0
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: row._headH
            color: Theme.panel2
            Text {
                objectName: "hotkeys-group-" + row.group
                anchors.left: parent.left; anchors.leftMargin: Theme.sp2xl
                anchors.verticalCenter: parent.verticalCenter
                text: row.group.length > 0 ? I18n.t("hotkeys.group." + row.group) : ""
                color: Theme.textDim
                font.pixelSize: Theme.fsSm
                font.weight: Theme.fwTitle
            }
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: Theme.border
            }
        }
        Item {
            id: rowBody
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 60
        }
        // The ListView hands focus to its current row; the row passes it to
        // its chip, so arrows + Enter work without the mouse.
        function focusChip() { rowChip.focusField(); }
        onActiveFocusChanged: if (activeFocus) rowChip.focusField()

        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 1; color: Theme.border
        }

        MouseArea { id: rowHover; anchors.fill: rowBody; hoverEnabled: true; acceptedButtons: Qt.NoButton }

        RowLayout {
            anchors.fill: rowBody
            anchors.leftMargin: Theme.sp2xl; anchors.rightMargin: Theme.spXl
            spacing: Theme.spLg

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: row.actionLabel
                    color: Theme.text
                    font.pixelSize: Theme.fsMd
                    font.weight: Theme.fwTitle
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: row.actionDescription
                    color: Theme.textMuted
                    font.pixelSize: Theme.fsXs
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            KeyCaptureChip {
                id: rowChip
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

        readonly property bool capturing: root.capturingId === chip.actionId && chip.actionId.length > 0
        property string candidate: ""
        property string conflictName: ""
        // The conflict is a built-in key (Ctrl+P, the board's arrows…): Enter
        // cannot take it, so the hint must not offer to (SHELL-4).
        property bool conflictBuiltin: false
        // Why the key cannot be had at all (the system keeps it), or "".
        property string reserved: ""
        onCapturingChanged: if (!capturing) { candidate = ""; conflictName = ""; conflictBuiltin = false; reserved = ""; }

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
                // Ctrl+= / Ctrl+- type no character on Windows, so the zoom
                // keys could not be recorded from ev.text.
                case Qt.Key_Equal:      return "=";
                case Qt.Key_Minus:      return "-";
                case Qt.Key_Plus:       return "+";
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

        // The chord as the router reads it: by the physical key, so "п" on a
        // Russian layout records "g" (APP-272).
        function _chord(ev) {
            return AppController.keyChord(ev.key, ev.modifiers, ev.text, ev.nativeScanCode);
        }
        // A bare key followed by another within a second records a two-key
        // sequence ("g b"); anything else starts over.
        property real _lastAt: 0
        function _append(chord) {
            const now = Date.now();
            const bare = !/(^|\+)(Ctrl|Alt|Meta)\+/.test(chord);
            const prev = chip.candidate;
            const prevBare = prev.length > 0 && prev.indexOf(", ") < 0 && !/(^|\+)(Ctrl|Alt|Meta)\+/.test(prev);
            const seq = bare && prevBare && now - chip._lastAt < 1000 ? prev + ", " + chord : chord;
            chip._lastAt = now;
            return seq;
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
            } else if (_namedKey(ev.key).length > 0) {
                // Before ev.text: Space types " ", which made "Ctrl+Shift+ "
                // and stored nothing (SHELL-5).
                key = _namedKey(ev.key);
            } else if (ev.text && ev.text.length > 0 && ev.text.charCodeAt(0) > 32) {
                key = ev.text;
                if (key.length === 1 && key.toLowerCase() !== key.toUpperCase())
                    key = key.toUpperCase();
            }
            if (!key || key.length === 0) return "";
            return mods.concat([key]).join("+");
        }

        function startCapture() {
            if (capturing) return;
            root.capturingId = actionId;
            candidate = sequence;
            conflictName = "";
            captureField.forceActiveFocus();
        }
        function focusField() { captureField.forceActiveFocus(); }
        function cancelCapture() {
            if (root.capturingId === actionId) root.capturingId = "";
        }
        // Capture what to store before letting go: setShortcut rebuilds the
        // list, which may destroy this chip before the call returns.
        function commit() {
            const id = actionId;
            const seq = candidate;
            const hadFocus = captureField.activeFocus;
            const panel = root;
            panel.capturingId = "";
            AppController.setShortcut(id, seq);
            // `root` is gone from this context by now if the chip was rebuilt.
            if (hadFocus) Qt.callLater(panel._refocusRow, id);
        }

        RowLayout {
            anchors.fill: parent
            spacing: Theme.spXs

            // ── chip (or capture field) ──────────────────
            Rectangle {
                id: chipBox
                Layout.fillWidth: true
                height: 26
                radius: Theme.radiusMd
                color: chip.capturing ? Theme.accentSoft : Theme.panel2
                border.color: captureField.activeFocus && !chip.capturing ? Theme.focusRing
                    : chip.capturing ? Theme.accent
                    : (chip.conflictName.length > 0 ? Theme.danger : Theme.border)
                border.width: captureField.activeFocus && !chip.capturing ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: chip.capturing
                        ? (chip.candidate.length > 0 ? AppController.keyText(chip.candidate) : I18n.t("hotkeys.recordPress"))
                        : (chip.sequence.length > 0 ? AppController.keyText(chip.sequence) : I18n.t("common.notSet"))
                    color: chip.capturing
                        ? (chip.candidate.length > 0 ? Theme.text : Theme.textDim)
                        : (chip.sequence.length > 0 ? Theme.text : Theme.textDim)
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsSm
                }

                // Focus receiver: Tab lands here; Enter or Space starts
                // recording, and while recording every key is captured.
                Item {
                    id: captureField
                    objectName: "hotkey-chip-" + chip.actionId
                    anchors.fill: parent
                    focus: chip.capturing
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    // An action with no key still has a name to read out
                    // (heap 2 left the single views unbound).
                    Accessible.name: chip.sequence.length > 0 ? AppController.keyText(chip.sequence) : I18n.t("common.notSet")
                    Keys.onPressed: (event) => {
                        // Not recording: this is a button. Enter used to
                        // commit an empty candidate and unbind the action, and
                        // a letter followed by Enter bound that bare letter
                        // with no capture UI showing.
                        if (!chip.capturing) {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                    || event.key === Qt.Key_Space) {
                                chip.startCapture();
                                event.accepted = true;
                            }
                            return;
                        }
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
                        const chord = chip._chord(event) || chip._buildSequenceString(event);
                        const seq = chord.length > 0 ? chip._append(chord) : "";
                        if (seq.length > 0) {
                            chip.candidate = seq;
                            chip.reserved = AppController.reservedShortcutReason(seq);
                            const conflictId = AppController.findShortcutConflict(chip.actionId, seq);
                            chip.conflictName = conflictId.length > 0
                                ? AppController.shortcutLabel(conflictId)
                                : "";
                            // A built-in key, or the start of another's
                            // sequence (g with g b): Enter cannot take it.
                            chip.conflictBuiltin = conflictId.length > 0
                                && (AppController.builtinShortcutConflict(chip.actionId, seq).length > 0
                                    || AppController.prefixShortcutConflict(chip.actionId, seq).length > 0);
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
                width: 22; height: 22; radius: Theme.radiusSm
                color: editMA.hovered ? Theme.panel3 : "transparent"
                border.color: Theme.border; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: chip.capturing ? "✓" : "✎"
                    color: chip.capturing ? Theme.accentStrong : Theme.textMuted
                    font.pixelSize: Theme.fsSm
                }
                // Named and with a tooltip, but not a Tab stop: the chip
                // beside it already records on Enter and saves on Enter.
                ClickArea {
                    id: editMA
                    objectName: "hotkeys-edit"
                    activeFocusOnTab: false
                    label: chip.capturing ? I18n.t("common.save") : I18n.t("hotkeys.edit")
                    onActivated: chip.capturing ? chip.commit() : chip.startCapture()
                }
            }

            Rectangle {
                width: 22; height: 22; radius: Theme.radiusSm
                visible: chip.sequence !== chip.defaultSequence
                color: resetMA.hovered ? Theme.panel3 : "transparent"
                border.color: Theme.border; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "↺"; color: Theme.textMuted; font.pixelSize: Theme.fsSm
                }
                ClickArea {
                    id: resetMA
                    objectName: "hotkeys-reset-" + chip.actionId
                    label: I18n.t("hotkeys.reset")
                    onActivated: {
                        const id = chip.actionId;
                        chip.cancelCapture();
                        AppController.resetShortcut(id);
                    }
                }
            }
        }

        // Conflict warning below the chip (only when capturing).
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -2
            visible: chip.capturing && (chip.conflictName.length > 0 || chip.reserved.length > 0)
            text: chip.reserved.length > 0 ? chip.reserved
                : I18n.t(chip.conflictBuiltin ? "hotkeys.conflict.builtin" : "hotkeys.conflict.body").arg(chip.conflictName)
            color: Theme.danger
            font.pixelSize: Theme.fsXs
            elide: Text.ElideRight
            width: parent.width
        }
    }

    // Dimmed backdrop is *not* used here — the panel is non-modal (mirrors Tweaks)
    // so the user can interact with the app while watching shortcuts.
}
