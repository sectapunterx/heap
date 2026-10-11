pragma ComponentBehavior: Bound

import QtQuick
import TodoCpp
import "ToastTiming.js" as Timing

// The notices at the bottom of the window (sheet X/N-Ntf-Toasts, DG-140).
//
// One at a time, bottom centre: a ring for the kind, the text, an underlined
// action and its key ("Готово: APP-112  Отменить  Ctrl Z"). The rest wait,
// counted as "+N" on the one on screen (and every notice is in the log). A
// toast with an action (Undo, Retry) is never pushed off: a plain notice
// gives way to a newcomer, an action toast makes the newcomer wait.
//
// show(message, kind) / showWithAction(message, label, seconds, fn, kind) as
// before; `kind` is "info" | "success" | "warning" | "error" and picks the
// ring. show(message, kind, tag): a
// plain notice with the same tag as one on screen takes its place instead of
// stacking ("Scale 110%" then "Scale 125%" while Ctrl+= is pressed).
//
// The toast sits on a popup's elevation. Its time (ToastTiming.js) stands
// still while the pointer or the keyboard is on it and while the window is in
// the background or minimized. An error is told by its shape and words, not
// by red (the sheet); the bold style tints the ring.
//
// The item spans the area the toasts may use (`areaWidth`, the work area in
// Main); the stack places itself inside it.
Item {
    id: root
    // The width the toast lives in: the work area beside the side rail.
    property real areaWidth: parent ? parent.width : 600
    // Always the bottom centre now (the sheet); kept for callers.
    readonly property bool wide: false
    // Never wider than this, whatever the message: a 1000px bar at 1100px
    // covered the board it was talking about. Long text wraps (three lines).
    readonly property real maxToastWidth: Math.max(0, Math.min(Theme.toastMaxWidth, areaWidth - 2 * Theme.sp3xl))
    readonly property int maxVisible: 1
    // Waiting behind the one on screen: "+N".
    readonly property int waiting: _queue.length

    // Whether someone can see the toasts: the window is in front and not
    // minimized. Bound to the window; a test sets it.
    property bool appVisible: Window.active && Window.visibility !== Window.Minimized
                              && Window.visibility !== Window.Hidden
    // The pointer is over the stack. Bound to the hover handler; a test
    // (offscreen, where nothing hovers) sets it.
    property bool hoverHeld: stackHover.hovered
    // The keyboard is on a toast's action.
    readonly property bool focusInside: {
        let it = Window.activeFocusItem;
        while (it) {
            if (it === root) return true;
            it = it.parent;
        }
        return false;
    }
    // Time stands still while the toasts cannot be read, or are being read.
    readonly property bool held: hoverHeld || focusInside || !appVisible

    // What is on screen (oldest first) and what is waiting.
    property var _items: []
    property var _queue: []
    property int _seq: 0
    // Toast ids that have played their entrance. The Repeater rebuilds every
    // card when the list changes; only a new one slides in. Mutated in place:
    // nothing binds to it.
    property var _entered: ({})
    // True the first time a card for this toast id is built.
    function _firstShow(id) {
        if (_entered[id]) return false;
        _entered[id] = true;
        return true;
    }

    // The newest visible toast, for callers and tests that read one.
    readonly property string message: _items.length ? _items[_items.length - 1].message : ""
    readonly property string kind: _items.length ? _items[_items.length - 1].kind : "info"
    readonly property string actionLabel: _items.length ? _items[_items.length - 1].actionLabel : ""
    readonly property int count: _items.length

    implicitWidth: stack.width
    implicitHeight: stack.height

    onHeldChanged: {
        const now = Date.now();
        for (let i = 0; i < _items.length; i++) {
            if (held) Timing.hold(_items[i], now);
            else Timing.resume(_items[i], now);
        }
        _tick();
    }

    function _duration(kind, seconds, hasAction) {
        return Timing.duration(kind, seconds, hasAction);
    }

    function _push(entry) {
        const now = Date.now();
        // An Undo toast names what Ctrl+Z takes back — the newest action. One
        // waiting behind an older Undo named the older action while Ctrl+Z
        // undid the newest (PERSONA-7): the newest replaces it.
        if (entry.undo) {
            _queue = _queue.filter(function (q) { return !q.undo; });
            const kept = _items.filter(function (it) { return !it.undo; });
            if (kept.length !== _items.length) _items = kept;
        }
        // The same plain notice twice in a row (a sync that keeps saying it is
        // running) refreshes the one on screen instead of stacking a copy.
        for (let i = 0; i < _items.length; i++) {
            const it = _items[i];
            const sameTag = !!entry.tag && it.tag === entry.tag;
            if (!it.actionLabel && !entry.actionLabel
                    && (sameTag || (it.message === entry.message && it.kind === entry.kind))) {
                it.message = entry.message;
                it.kind = entry.kind;
                Timing.start(it, entry.ms, now, held);
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
        Timing.start(entry, entry.ms, now, held);
        _items = _items.concat([entry]);
        _tick();
    }

    function show(s, k, tag) {
        _push({ id: ++_seq, message: String(s), kind: k || "info", actionLabel: "", actionFn: null,
                ms: _duration(k || "info", 0, false), tag: tag || "" });
    }
    // `key`: the shortcut that does the action too, shown after it ("Ctrl Z").
    function showWithAction(s, label, seconds, fn, k, key) {
        _push({ id: ++_seq, message: String(s), kind: k || "info", actionLabel: label || "",
                actionFn: fn, action2Label: "", action2Fn: null, key: key || "",
                ms: _duration(k || "info", seconds, !!label) });
    }
    // An Undo for the action just done (Main.onUndoableToast): replaces an
    // older Undo on screen, and loses its action when the history goes.
    function showUndo(s, label, seconds, fn, k, key) {
        _push({ id: ++_seq, message: String(s), kind: k || "info", actionLabel: label || "",
                actionFn: fn, action2Label: "", action2Fn: null, key: key || "", undo: true,
                ms: _duration(k || "info", seconds, !!label) });
    }
    // The undo history is gone (a profile switch, the action undone with
    // Ctrl+Z): an Undo toast that stays up offered a button that did nothing
    // (IDIOT-SHELL-4). It keeps its words and drops the action.
    function dropUndo() {
        let changed = false;
        const strip = function (e) {
            if (!e.undo || !e.actionLabel) return;
            e.actionLabel = "";
            e.actionFn = null;
            e.key = "";
            changed = true;
        };
        _items.forEach(strip);
        _queue.forEach(strip);
        if (changed) _items = _items.slice();
    }
    // Up to three actions side by side ([{label, fn}, …]): "Open in
    // tracker" / "Archive" for a refused move (APP-204); open / in 15 min /
    // next free window on a task block's start (APP-256). Same look, same
    // clock: an action keeps it up at least ToastTiming.ACTION_MS.
    function showWithActions(s, actions, seconds, k) {
        const a = actions || [];
        const label = a.length > 0 ? String(a[0].label) : "";
        _push({ id: ++_seq, message: String(s), kind: k || "info",
                actionLabel: label, actionFn: a.length > 0 ? a[0].fn : null,
                action2Label: a.length > 1 ? String(a[1].label) : "", action2Fn: a.length > 1 ? a[1].fn : null,
                action3Label: a.length > 2 ? String(a[2].label) : "", action3Fn: a.length > 2 ? a[2].fn : null,
                ms: _duration(k || "info", seconds, a.length > 0) });
    }

    function dismiss(id) {
        const next = [];
        for (let i = 0; i < _items.length; i++) if (_items[i].id !== id) next.push(_items[i]);
        _items = next;
        _promote();
    }
    function clear() { _items = []; _queue = []; expiry.stop(); }

    function _promote() {
        const now = Date.now();
        while (_queue.length && _items.length < maxVisible) {
            const e = _queue[0];
            _queue = _queue.slice(1);
            Timing.start(e, e.ms, now, held);
            _items = _items.concat([e]);
        }
        _tick();
    }

    // One timer for the stack: wakes for the next toast to run out. While
    // the stack is held nothing counts down, and the timer sleeps.
    function _tick() {
        const s = Timing.sweep(_items, Date.now());
        if (s.expired > 0) {
            _items = s.keep;
            if (_queue.length) { _promote(); return; }
        }
        if (s.next < Infinity) {
            expiry.interval = Math.max(16, s.next);
            expiry.restart();
        } else {
            expiry.stop();
        }
    }
    Timer { id: expiry; repeat: false; onTriggered: root._tick() }

    Column {
        id: stack
        objectName: "toast-stack"
        // Bottom-right of a wide work area, bottom centre of a narrow one.
        x: root.wide ? root.width - width - Theme.sp3xl : Math.round((root.width - width) / 2)
        anchors.bottom: parent.bottom
        spacing: Theme.spMd

        HoverHandler { id: stackHover }

        Repeater {
            model: root._items
            delegate: Item {
                id: card
                required property var modelData
                objectName: "toast-card"
                readonly property color kindColor: Theme.toastKindColor(modelData.kind)
                readonly property bool alert: modelData.kind === "warning" || modelData.kind === "error"
                readonly property int leftPad: Theme.spXl
                readonly property int rightPad: Theme.spXl
                // Whether this card plays its entrance (a new toast, not a
                // rebuilt one) — read by tests.
                property bool entering: false
                // What the card reads from the stack.
                readonly property bool wide: root.wide
                readonly property real cap: root.maxToastWidth
                readonly property real lane: stack.width

                width: Math.min(card.cap, rowL.implicitWidth + card.leftPad + card.rightPad)
                height: Math.max(Theme.px(40), rowL.implicitHeight + 2 * Theme.spMd)
                x: card.wide ? card.lane - card.width : Math.round((card.lane - card.width) / 2)
                Accessible.role: Accessible.AlertMessage
                Accessible.name: modelData.message
                transform: Translate { id: slide; objectName: "toast-slide"; y: 0 }

                // Either action closes the toast, then runs.
                function runAction(fn) {
                    root.dismiss(card.modelData.id);
                    if (typeof fn === "function") fn();
                }

                Component.onCompleted: {
                    const id = card.modelData.id;
                    if (!root._firstShow(id)) return;
                    card.entering = true;
                    if (Theme.reducedMotion) return;   // appear, no movement
                    slide.y = Theme.toastSlide;
                    card.opacity = 0;
                    enter.start();
                }

                ParallelAnimation {
                    id: enter
                    NumberAnimation { target: slide; property: "y"; to: 0; duration: Theme.durMove; easing.type: Theme.easeEnter }
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: Theme.durMove; easing.type: Theme.easeEnter }
                }

                ElevationShadow {
                    color: Theme.popupShadow
                    offset: Theme.popupShadowOffset
                    depth: Theme.popupShadowDepth
                    radius: Theme.popupRadius
                }

                Rectangle {
                    id: face
                    anchors.fill: parent
                    radius: Theme.popupRadius
                    color: Theme.toastBg
                    border.color: Theme.toastBorder
                    border.width: 1
                }

                Row {
                    id: rowL
                    x: card.leftPad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spLg
                    // The kind as a shape (StatusRing): done = filled,
                    // notice = ring, warning = a quarter, error = a barred
                    // ring. Coloured only in the bold style.
                    StatusRing {
                        objectName: "toast-kind-icon"
                        anchors.verticalCenter: parent.verticalCenter
                        size: Theme.px(12)
                        category: card.modelData.kind === "success" ? "done"
                                : card.modelData.kind === "warning" ? "half"
                                : card.modelData.kind === "error" ? "blocked" : "todo"
                        ink: Style.chipFill ? card.kindColor
                           : card.modelData.kind === "error" ? Theme.text
                           : card.modelData.kind === "info" ? Theme.textDim : Theme.textMuted
                    }
                    Text {
                        id: msgT
                        objectName: "toast-message"
                        anchors.verticalCenter: parent.verticalCenter
                        // Wraps inside the card's cap instead of growing it.
                        width: Math.min(implicitWidth,
                                        card.cap - card.leftPad - card.rightPad - Theme.px(12) - rowL.spacing
                                        - (moreT.visible ? moreT.implicitWidth + rowL.spacing : 0)
                                        - (keyT.visible ? keyT.implicitWidth + rowL.spacing : 0)
                                        - (actionBox.visible ? actionBox.implicitWidth + rowL.spacing : 0)
                                        - (action2Box.visible ? action2Box.implicitWidth + rowL.spacing : 0)
                                        - (action3Box.visible ? action3Box.implicitWidth + rowL.spacing : 0))
                        text: card.modelData.message
                        textFormat: Text.PlainText
                        color: Theme.toastText
                        font.pixelSize: Theme.fsMd
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    Text {
                        id: moreT
                        objectName: "toast-more"
                        visible: root.waiting > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "+" + root.waiting
                        color: Theme.textDim
                        font.pixelSize: Theme.fsMd
                    }
                    Rectangle {
                        id: actionBox
                        visible: card.modelData.actionLabel.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"
                        implicitWidth: actionT.implicitWidth
                        implicitHeight: actionT.implicitHeight + 2 * Theme.spXs
                        Text {
                            id: actionT
                            anchors.centerIn: parent
                            text: card.modelData.actionLabel
                            color: Theme.toastText
                            font.pixelSize: Theme.fsMd
                            font.underline: true
                        }
                        ClickArea {
                            id: actionMA
                            objectName: "toast-action"
                            label: card.modelData.actionLabel
                            showTip: false
                            onActivated: card.runAction(card.modelData.actionFn)
                        }
                    }
                    // The second action of showWithActions (APP-204).
                    Rectangle {
                        id: action2Box
                        visible: !!card.modelData.action2Label && card.modelData.action2Label.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"
                        implicitWidth: action2T.implicitWidth
                        implicitHeight: action2T.implicitHeight + 2 * Theme.spXs
                        Text {
                            id: action2T
                            anchors.centerIn: parent
                            text: card.modelData.action2Label || ""
                            color: Theme.toastText
                            font.pixelSize: Theme.fsMd
                            font.underline: true
                        }
                        ClickArea {
                            id: action2MA
                            objectName: "toast-action-2"
                            label: card.modelData.action2Label || ""
                            showTip: false
                            onActivated: card.runAction(card.modelData.action2Fn)
                        }
                    }
                    // The third (APP-256).
                    Rectangle {
                        id: action3Box
                        visible: !!card.modelData.action3Label && card.modelData.action3Label.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"
                        implicitWidth: action3T.implicitWidth
                        implicitHeight: action3T.implicitHeight + 2 * Theme.spXs
                        Text {
                            id: action3T
                            anchors.centerIn: parent
                            text: card.modelData.action3Label || ""
                            color: Theme.toastText
                            font.pixelSize: Theme.fsMd
                            font.underline: true
                        }
                        ClickArea {
                            id: action3MA
                            objectName: "toast-action-3"
                            label: card.modelData.action3Label || ""
                            showTip: false
                            onActivated: card.runAction(card.modelData.action3Fn)
                        }
                    }
                    Text {
                        id: keyT
                        objectName: "toast-key"
                        visible: !!card.modelData.key && card.modelData.key.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.modelData.key || ""
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsXs
                    }
                }
            }
        }
    }
}
