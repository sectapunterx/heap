.pragma library

// Which popup a press on the window overlay belongs to (APP-126).
//
// A press beside a dialog closes it. Dialogs that guard unsaved input own
// their close (NoAutoClose plus a discard check), so they listen to the
// overlay's pressed() instead of Qt's close policy. A dimmer item under the
// dialog never sees that press, which is why the old backdrop handlers in
// TaskEditor and EventEditor never fired. But pressed() goes to every
// visible popup, so a dialog acts only when it is the top one: a press
// beside an open date picker or discard prompt is that popup's to handle.

// True when `popup` is drawn above everything else on `overlay`. Dimmers
// sit just below their own popup, so the last visible child with the highest
// z is always a popup's item.
function isTopmost(popup, overlay) {
    if (!popup || !overlay || !popup.opened || !popup.contentItem)
        return false;
    var mine = popup.contentItem.parent;
    var top = null;
    var kids = overlay.children;
    for (var i = 0; i < kids.length; i++) {
        var k = kids[i];
        if (k.visible && (top === null || k.z >= top.z))
            top = k;
    }
    return top !== null && top === mine;
}
