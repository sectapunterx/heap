import QtQuick
import TodoCpp

// "You've seen this before" (APP-159): one quiet line under a field —
//
//   Looks like this came up before: “Login 500 after deploy” · 12 Sep
//
// — when what is in the field looks like an error or a stack trace and the
// user's own notes, docs or tasks already mention it. Clicking it opens that
// place. Looked up a moment after typing stops; nothing networked, nothing
// done beyond showing the line. Off unless Settings → Safety net turns it on.
Item {
    id: root
    // The text to look at, and the task being edited (which would otherwise
    // find itself).
    property string text: ""
    property string excludeTaskId: ""
    property var hit: ({})
    readonly property bool shown: !!(root.hit && root.hit.id)
    readonly property bool enabledInSettings: !!(AppController.safety && AppController.safety.seenBefore)

    signal activated(var hit)

    visible: root.shown
    implicitWidth: line.implicitWidth
    implicitHeight: root.shown ? line.implicitHeight : 0

    onTextChanged: lookup.restart()
    onEnabledInSettingsChanged: lookup.restart()

    Timer {
        id: lookup
        interval: 400
        onTriggered: root.refresh()
    }

    function refresh() {
        if (!root.enabledInSettings || root.text.length < 8) {
            root.hit = ({});
            return;
        }
        root.hit = AppController.seenBefore(root.text, root.excludeTaskId);
    }

    function _date(d) {
        return I18n.fmtDate(d, "dayMonth");
    }

    Text {
        id: line
        objectName: "seen-before-hint"
        width: root.width
        text: {
            if (!root.shown) return "";
            const when = root._date(root.hit.date);
            const base = I18n.t("seen.hint").arg(root.hit.title);
            return when.length > 0 ? base + " · " + when : base;
        }
        textFormat: Text.PlainText
        color: hintArea.hovered ? Theme.accentStrong : Theme.textMuted
        font.pixelSize: Theme.fsXs
        font.underline: hintArea.hovered
        elide: Text.ElideRight
        ClickArea {
            id: hintArea
            objectName: "seen-before-open"
            label: I18n.t("seen.open")
            showTip: false
            onActivated: root.activated(root.hit)
        }
    }
}
