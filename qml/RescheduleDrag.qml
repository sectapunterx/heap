// heap. — the drag that moves a task to another date (APP-249).
//
// One per view (Week, Month, Timeline), laid over it. The view's own pointer
// handler does the hit-testing; this draws what is being carried and where it
// would land — "When → Thu, Oct 15, 14:00", "Deadline → none" — at the pointer,
// and owns Esc: while a drag is on, the keyboard is here, so Esc cancels the
// drag and nothing else (not the view's or the window's own Esc).
//
// No motion of its own: the ghost follows the pointer and a cancel simply
// drops it, so Reduce motion has nothing to take away.
import QtQuick
import TodoCpp

Item {
    id: rd
    anchors.fill: parent
    z: 50

    property bool active: false
    property string taskId: ""
    property string title: ""
    // What a drop here would do, said at the pointer; `ok` false greys it out.
    property string hint: ""
    property bool ok: false
    property real px: 0
    property real py: 0
    // False when the thing dragged moves itself (a block on the week grid):
    // then only the hint follows the pointer.
    property bool carry: true

    // Esc, while a drag is on. The view puts everything back.
    signal canceled()

    property var _prevFocus: null

    function begin(id, label, carry) {
        rd.carry = carry !== false;
        rd.taskId = String(id);
        rd.title = String(label || "");
        rd.hint = "";
        rd.ok = false;
        rd.active = true;
        rd._prevFocus = rd.Window.activeFocusItem;
        catcher.forceActiveFocus();
    }
    // `x`, `y` in this item's coordinates.
    function update(x, y, hintText, isOk) {
        rd.px = x;
        rd.py = y;
        rd.hint = hintText || "";
        rd.ok = !!isOk;
    }
    function finish() {
        if (!rd.active) return;
        rd.active = false;
        rd.hint = "";
        const back = rd._prevFocus;
        rd._prevFocus = null;
        if (back && back.forceActiveFocus) back.forceActiveFocus();
    }
    function cancel() {
        if (!rd.active) return;
        rd.finish();
        rd.canceled();
    }

    // "When → …" / "Deadline → …": `field` is "scheduled" or "due".
    function describe(field, when, timed) {
        const name = I18n.t(field === "due" ? "drag.field.due" : "drag.field.scheduled");
        const at = timed ? I18n.fmtDateTime(when, "weekdayDay") : I18n.fmtDate(when, "weekdayDay");
        return I18n.t("drag.hint").arg(name).arg(at);
    }
    function describeClear(field) {
        return I18n.t("drag.hint").arg(I18n.t(field === "due" ? "drag.field.due" : "drag.field.scheduled"))
                                 .arg(I18n.t("drag.none"));
    }

    Item {
        id: catcher
        objectName: "reschedule-esc"
        // The window's own Esc shortcuts (clear selection, leave focus mode)
        // must not see this one.
        Keys.onShortcutOverride: (event) => {
            if (rd.active && event.key === Qt.Key_Escape) event.accepted = true;
        }
        Keys.onPressed: (event) => {
            if (rd.active && event.key === Qt.Key_Escape) {
                rd.cancel();
                event.accepted = true;
            }
        }
    }

    // What is being carried.
    Rectangle {
        id: ghost
        objectName: "reschedule-ghost"
        visible: rd.active && rd.carry
        x: Math.min(rd.width - width, rd.px + Theme.spMd)
        y: Math.min(rd.height - height - hintBox.height - Theme.spXs, rd.py + Theme.spMd)
        width: Math.min(Theme.px(220), ghostText.implicitWidth + 2 * Theme.spMd)
        height: Theme.px(24)
        radius: Theme.radiusSm
        color: Theme.panel3
        border.color: Theme.accent
        border.width: 1
        Text {
            id: ghostText
            anchors.fill: parent
            anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
            verticalAlignment: Text.AlignVCenter
            text: rd.title
            textFormat: Text.PlainText
            color: Theme.text
            font.pixelSize: Theme.fsXs
            elide: Text.ElideRight
        }
    }

    // Where it would land.
    Rectangle {
        id: hintBox
        objectName: "reschedule-hint"
        visible: rd.active && rd.hint.length > 0
        x: ghost.x
        y: rd.carry ? ghost.y + ghost.height + Theme.spXs : Math.min(rd.height - height, rd.py + Theme.spMd)
        width: hintText.implicitWidth + 2 * Theme.spMd
        height: Theme.px(22)
        radius: Theme.radiusSm
        color: rd.ok ? Theme.accentSoft : Theme.panel2
        border.color: rd.ok ? Theme.withAlpha(Theme.accent, 0.5) : Theme.border
        border.width: 1
        Text {
            id: hintText
            objectName: "reschedule-hint-text"
            anchors.centerIn: parent
            text: rd.hint
            textFormat: Text.PlainText
            color: rd.ok ? Theme.accentStrong : Theme.textDim
            font.family: Theme.fontUi
            font.features: Theme.tabularNums
            font.pixelSize: Theme.fsXs
        }
    }
}
