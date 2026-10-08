pragma ComponentBehavior: Bound

import QtQuick
import TodoCpp
import "ToastTiming.js" as Timing

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
// before; `kind` is "info" | "success" | "warning" | "error" and picks the
// icon and the border; a warning or an error also gets a bar on the left and
// one soft pulse of its border when it arrives. show(message, kind, tag): a
// plain notice with the same tag as one on screen takes its place instead of
// stacking ("Scale 110%" then "Scale 125%" while Ctrl+= is pressed).
//
// APP-225: on a big monitor the old 13px bar at the bottom centre was gone
// before anyone saw it. The type is a step larger, the toast sits on a
// popup's elevation, and in a wide work area the stack moves to its
// bottom-right corner. Its time (ToastTiming.js) stands still while the
// pointer or the keyboard is on it and while the window is in the
// background or minimized.
//
// The item spans the area the toasts may use (`areaWidth`, the work area in
// Main); the stack places itself inside it.
Item {
    id: root
    // The width the stack lives in: the work area beside the side rail and
    // the right panel. Decides between the corner and the centre.
    property real areaWidth: parent ? parent.width : 600
    readonly property bool wide: Timing.corner(areaWidth, Theme.toastWideFrom)
    // Never wider than this, whatever the message: a 1000px bar at 1100px
    // covered the board it was talking about. Long text wraps (three lines).
    readonly property real maxToastWidth: Math.max(0, Math.min(Theme.toastMaxWidth, areaWidth - 2 * Theme.sp3xl))
    readonly property int maxVisible: 3

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
    function showWithAction(s, label, seconds, fn, k) {
        _push({ id: ++_seq, message: String(s), kind: k || "info", actionLabel: label || "",
                actionFn: fn, ms: _duration(k || "info", seconds, !!label) });
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
                // Room on the left for the accent bar.
                readonly property int leftPad: Theme.sp2xl + (alert ? Theme.toastAccentWidth + Theme.spSm : 0)
                readonly property int rightPad: Theme.sp2xl
                // Whether this card plays its entrance (a new toast, not a
                // rebuilt one) — read by tests.
                property bool entering: false
                // What the card reads from the stack.
                readonly property bool wide: root.wide
                readonly property real cap: root.maxToastWidth
                readonly property real lane: stack.width

                width: Math.min(card.cap, rowL.implicitWidth + card.leftPad + card.rightPad)
                height: rowL.implicitHeight + 2 * Theme.spXl
                x: card.wide ? card.lane - card.width : Math.round((card.lane - card.width) / 2)
                Accessible.role: Accessible.AlertMessage
                Accessible.name: modelData.message
                transform: Translate { id: slide; objectName: "toast-slide"; y: 0 }

                Component.onCompleted: {
                    const id = card.modelData.id;
                    if (!root._firstShow(id)) return;
                    card.entering = true;
                    if (Theme.reducedMotion) return;   // appear, no movement
                    slide.y = Theme.toastSlide;
                    card.opacity = 0;
                    enter.start();
                    if (card.alert) pulse.start();
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
                    border.color: card.alert ? card.kindColor : Theme.toastBorder
                    border.width: 1
                }

                // A warning or an error: a bar down the left edge.
                Rectangle {
                    objectName: "toast-accent"
                    visible: card.alert
                    x: Theme.spMd
                    y: Theme.spMd
                    width: Theme.toastAccentWidth
                    height: card.height - 2 * Theme.spMd
                    radius: width / 2
                    color: card.kindColor
                }

                // One soft pulse of the border as a warning or an error
                // arrives, so it is seen on the far side of the screen.
                Rectangle {
                    id: glow
                    objectName: "toast-pulse"
                    anchors.fill: parent
                    anchors.margins: -Theme.sp2xs
                    radius: face.radius + Theme.sp2xs
                    color: "transparent"
                    border.color: card.kindColor
                    border.width: Theme.sp2xs
                    opacity: 0
                    SequentialAnimation {
                        id: pulse
                        NumberAnimation { target: glow; property: "opacity"; to: 0.9; duration: Theme.durMove; easing.type: Theme.easePulse }
                        NumberAnimation { target: glow; property: "opacity"; to: 0; duration: Theme.durPulse; easing.type: Theme.easePulse }
                    }
                }

                Row {
                    id: rowL
                    x: card.leftPad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spLg

                    // The kind, as a shape and not only a colour.
                    Rectangle {
                        objectName: "toast-kind-icon"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.toastIcon
                        height: Theme.toastIcon
                        radius: width / 2
                        color: "transparent"
                        border.color: card.kindColor
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: card.modelData.kind === "error" ? "✕"
                                : card.modelData.kind === "warning" ? "!"
                                : card.modelData.kind === "success" ? "✓" : "i"
                            color: card.kindColor
                            font.pixelSize: Theme.fsSm
                            font.weight: Theme.fwTitle
                        }
                    }
                    Text {
                        id: msgT
                        objectName: "toast-message"
                        anchors.verticalCenter: parent.verticalCenter
                        // Wraps inside the card's cap instead of growing it.
                        width: Math.min(implicitWidth,
                                        card.cap - card.leftPad - card.rightPad - Theme.toastIcon - rowL.spacing
                                        - (actionBox.visible ? actionBox.implicitWidth + rowL.spacing : 0))
                        text: card.modelData.message
                        textFormat: Text.PlainText
                        color: Theme.toastText
                        font.pixelSize: Theme.fsLg
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
                        implicitWidth: actionT.implicitWidth + 2 * Theme.spLg
                        implicitHeight: actionT.implicitHeight + 2 * Theme.spXs
                        Text {
                            id: actionT
                            anchors.centerIn: parent
                            text: card.modelData.actionLabel
                            color: Theme.accentStrong
                            font.pixelSize: Theme.fsMd
                            font.weight: Theme.fwTitle
                        }
                        ClickArea {
                            id: actionMA
                            objectName: "toast-action"
                            label: card.modelData.actionLabel
                            showTip: false
                            onActivated: {
                                const fn = card.modelData.actionFn;
                                root.dismiss(card.modelData.id);
                                if (typeof fn === "function") fn();
                            }
                        }
                    }
                }
            }
        }
    }
}
