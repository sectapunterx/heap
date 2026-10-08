import QtQuick
import TodoCpp

// The notices at the bottom of the window.
//
// It used to be one slot: a later toast replaced the one on screen, so an
// "Undo" was lost the moment anything else said something (a save, a sync).
// Toasts now stack — newest at the bottom, up to `maxVisible` at once — and the
// rest wait their turn. A toast with an action (Undo, Retry) is never pushed
// off: when the stack is full a plain notice makes room first, and if every
// visible toast has an action, the newcomer waits.
//
// show(message, kind) / showWithAction(message, label, seconds, fn, kind) as
// before; `kind` is "info" | "success" | "warning" | "error" and tints the dot
// and border. Errors stay up longer. show(message, kind, tag): a plain notice
// with the same tag as one on screen takes its place instead of stacking
// ("Scale 110%" then "Scale 125%" while Ctrl+= is pressed).
Item {
    id: root
    // Never wider than this, whatever the message: a 1000px bar at 1100px
    // covered the board it was talking about. Long text wraps (three lines).
    readonly property real maxToastWidth: Math.min(560, (parent ? parent.width : 600) - 48)
    readonly property int maxVisible: 3

    // What is on screen (oldest first) and what is waiting.
    property var _items: []
    property var _queue: []
    property int _seq: 0

    // The newest visible toast, for callers and tests that read one.
    readonly property string message: _items.length ? _items[_items.length - 1].message : ""
    readonly property string kind: _items.length ? _items[_items.length - 1].kind : "info"
    readonly property string actionLabel: _items.length ? _items[_items.length - 1].actionLabel : ""
    readonly property int count: _items.length

    implicitWidth: stack.implicitWidth
    implicitHeight: stack.implicitHeight
    width: implicitWidth
    height: implicitHeight

    function _duration(kind, seconds) {
        if (seconds && seconds > 0) return seconds * 1000;
        return kind === "error" ? 6000 : kind === "warning" ? 4000 : 2400;
    }

    function _push(entry) {
        // The same plain notice twice in a row (a sync that keeps saying it is
        // running) refreshes the one on screen instead of stacking a copy.
        for (let i = 0; i < _items.length; i++) {
            const it = _items[i];
            const sameTag = !!entry.tag && it.tag === entry.tag;
            if (!it.actionLabel && !entry.actionLabel
                    && (sameTag || (it.message === entry.message && it.kind === entry.kind))) {
                it.message = entry.message;
                it.kind = entry.kind;
                it.expires = Date.now() + entry.ms;
                _items = _items.slice();
                _tick();
                return;
            }
        }
        if (_items.length >= maxVisible) {
            // Make room by retiring the oldest plain notice.
            let drop = -1;
            for (let i = 0; i < _items.length; i++) if (!_items[i].actionLabel) { drop = i; break; }
            if (drop < 0) { _queue = _queue.concat([entry]); return; }
            const next = _items.slice();
            next.splice(drop, 1);
            _items = next;
        }
        entry.expires = Date.now() + entry.ms;
        _items = _items.concat([entry]);
        _tick();
    }

    function show(s, k, tag) {
        _push({ id: ++_seq, message: String(s), kind: k || "info", actionLabel: "", actionFn: null,
                ms: _duration(k || "info", 0), tag: tag || "" });
    }
    function showWithAction(s, label, seconds, fn, k) {
        _push({ id: ++_seq, message: String(s), kind: k || "info", actionLabel: label || "",
                actionFn: fn, action2Label: "", action2Fn: null,
                ms: _duration(k || "info", seconds && seconds > 0 ? seconds : 5) });
    }
    // Two actions side by side ([{label, fn}, {label, fn}]): "Open in
    // tracker" / "Archive" for a refused move (APP-204).
    function showWithActions(s, actions, seconds, k) {
        const a = actions || [];
        _push({ id: ++_seq, message: String(s), kind: k || "info",
                actionLabel: a.length > 0 ? String(a[0].label) : "", actionFn: a.length > 0 ? a[0].fn : null,
                action2Label: a.length > 1 ? String(a[1].label) : "", action2Fn: a.length > 1 ? a[1].fn : null,
                ms: _duration(k || "info", seconds && seconds > 0 ? seconds : 5) });
    }

    function dismiss(id) {
        const next = [];
        for (let i = 0; i < _items.length; i++) if (_items[i].id !== id) next.push(_items[i]);
        _items = next;
        _promote();
    }
    function clear() { _items = []; _queue = []; }

    function _promote() {
        while (_queue.length && _items.length < maxVisible) {
            const e = _queue[0];
            _queue = _queue.slice(1);
            e.expires = Date.now() + e.ms;
            _items = _items.concat([e]);
        }
        _tick();
    }

    // One timer for the stack: wakes for the next toast to expire.
    function _tick() {
        const now = Date.now();
        const keep = [];
        let next = Infinity;
        for (let i = 0; i < _items.length; i++) {
            if (_items[i].expires <= now) continue;
            keep.push(_items[i]);
            next = Math.min(next, _items[i].expires);
        }
        if (keep.length !== _items.length) {
            _items = keep;
            if (_queue.length) { _promote(); return; }
        }
        if (next < Infinity) {
            expiry.interval = Math.max(16, next - now);
            expiry.restart();
        } else {
            expiry.stop();
        }
    }
    Timer { id: expiry; repeat: false; onTriggered: root._tick() }

    Column {
        id: stack
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        spacing: Theme.spSm
        Repeater {
            model: root._items
            delegate: Rectangle {
                id: card
                required property var modelData
                objectName: "toast-card"
                anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                readonly property color kindColor: Theme.alertColor(modelData.kind)
                radius: Theme.radius
                color: Theme.toastBg
                border.color: modelData.kind === "info" ? Theme.toastBorder : Theme.withAlpha(kindColor, 0.6)
                border.width: 1
                width: Math.min(root.maxToastWidth, rowL.implicitWidth + 28)
                height: rowL.implicitHeight + 14
                Accessible.role: Accessible.AlertMessage
                Accessible.name: modelData.message
                function runAction(fn) {
                    root.dismiss(card.modelData.id);
                    if (typeof fn === "function") fn();
                }

                Row {
                    id: rowL
                    anchors.centerIn: parent
                    spacing: Theme.spXl
                    Rectangle {
                        objectName: "toast-kind-dot"
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: card.kindColor
                    }
                    Text {
                        id: msgT
                        objectName: "toast-message"
                        anchors.verticalCenter: parent.verticalCenter
                        // Wraps inside the card's cap instead of growing it.
                        width: Math.min(implicitWidth,
                                        root.maxToastWidth - 28 - 8 - rowL.spacing
                                        - (actionBox.visible ? actionBox.implicitWidth + rowL.spacing : 0)
                                        - (action2Box.visible ? action2Box.implicitWidth + rowL.spacing : 0))
                        text: card.modelData.message
                        textFormat: Text.PlainText
                        color: Theme.toastText
                        font.pixelSize: Theme.fsMd
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        id: actionBox
                        visible: card.modelData.actionLabel.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.radiusSm
                        color: actionMA.hovered ? Theme.accentSoft : "transparent"
                        border.color: Theme.accent
                        border.width: 1
                        implicitWidth: actionT.implicitWidth + 14
                        implicitHeight: actionT.implicitHeight + 6
                        Text {
                            id: actionT
                            anchors.centerIn: parent
                            text: card.modelData.actionLabel
                            color: Theme.accentStrong
                            font.pixelSize: Theme.fsSm
                            font.weight: Theme.fwTitle
                        }
                        ClickArea {
                            id: actionMA
                            objectName: "toast-action"
                            label: card.modelData.actionLabel
                            showTip: false
                            onActivated: card.runAction(card.modelData.actionFn)
                        }
                    }
                    Rectangle {
                        id: action2Box
                        visible: !!card.modelData.action2Label && card.modelData.action2Label.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.radiusSm
                        color: action2MA.hovered ? Theme.accentSoft : "transparent"
                        border.color: Theme.accent
                        border.width: 1
                        implicitWidth: action2T.implicitWidth + 14
                        implicitHeight: action2T.implicitHeight + 6
                        Text {
                            id: action2T
                            anchors.centerIn: parent
                            text: card.modelData.action2Label || ""
                            color: Theme.accentStrong
                            font.pixelSize: Theme.fsSm
                            font.weight: Theme.fwTitle
                        }
                        ClickArea {
                            id: action2MA
                            objectName: "toast-action-2"
                            label: card.modelData.action2Label || ""
                            showTip: false
                            onActivated: card.runAction(card.modelData.action2Fn)
                        }
                    }
                }
            }
        }
    }
}
