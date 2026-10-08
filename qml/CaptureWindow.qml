import QtQuick
import QtQuick.Window
import TodoCpp

// The global capture hotkeys fired while heap is not the focused window. The
// capture popups come up in a small window of their own, over whatever the
// user is doing, and the main window stays where it was — minimized, in the
// tray or behind other apps. Esc, a save or clicking away puts it away again.
Window {
    id: cap
    objectName: "capture-window"
    // Tool: no taskbar button. StaysOnTop: it is summoned over other apps and
    // must not open behind the one that has focus.
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    width: 680
    height: 520
    visible: false
    title: "heap."

    // Screen the window opens on; the owner passes its own, which is where the
    // user last looked at heap.
    property var hostScreen: null

    // Forwarded from either popup: what was just created.
    signal captured(string title, string body, string taskId)
    // A "seen this before" hint was clicked (APP-159): heap opens the place.
    signal seenBeforeActivated(var hit)

    readonly property bool busy: task.opened || note.opened
    property bool _wasActive: false

    // `mode` is "task" or "note". A second press while it is up switches to the
    // other popup, or just brings the same one forward — reopening would wipe
    // what has been typed so far.
    function summon(mode) {
        const want = mode === "note" ? note : task;
        const other = mode === "note" ? task : note;
        if (other.opened) other.close();
        if (!cap.visible) {
            // hostScreen is a QScreen (Window.screen); its geometry is in
            // virtual-desktop coordinates, which is what x/y take.
            let g = Qt.rect(Screen.virtualX, Screen.virtualY, Screen.width, Screen.height);
            if (cap.hostScreen && cap.hostScreen.availableGeometry) {
                cap.screen = cap.hostScreen;
                g = cap.hostScreen.availableGeometry;
            }
            cap.x = g.x + Math.round((g.width - cap.width) / 2);
            cap.y = g.y + Math.round(g.height * 0.18);
            cap._wasActive = false;
            cap.show();
        }
        cap.raise();
        cap.requestActivate();
        if (!want.opened) want.open();
    }

    function _maybeHide() {
        if (!cap.busy) cap.hide();
    }

    // Clicking away counts as dismissing it — the task popup's
    // CloseOnPressOutside, for a click that lands outside the window. A note
    // with text in it stays: it has no undo, so it waits for Esc or
    // Ctrl+Enter (Enter is a new line in both popups, APP-209).
    onActiveChanged: {
        if (cap.active) {
            cap._wasActive = true;
            return;
        }
        if (!cap._wasActive || !cap.visible) return;
        if (task.opened) task.close();
        if (note.opened && !note.hasText) note.close();
    }

    QuickCapturePopup {
        id: task
        objectName: "capture-task"
        standalone: true
        onClosed: Qt.callLater(cap._maybeHide)
        onCaptured: (title, body, taskId) => cap.captured(title, body, taskId)
        onSeenBeforeActivated: (hit) => {
            task.close();
            cap.seenBeforeActivated(hit);
        }
    }
    QuickCaptureNotesPopup {
        id: note
        objectName: "capture-note"
        standalone: true
        onClosed: Qt.callLater(cap._maybeHide)
        onCaptured: (title, body, taskId) => cap.captured(title, body, taskId)
    }
}
