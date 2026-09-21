import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// A markdown document, edited and previewed.
//
// NotesView grew one of these over a thousand lines, wired directly to
// `notesState`. Docs pages want the same thing pointed at a different document,
// so this is the part that does not care which: hand it a page id, it loads the
// body, debounces the writes and flushes on the way out.
//
// The debounce is the reason `flush()` is public. A caller that switches
// documents has to call it first, or the last keystrokes are still only in the
// text field and switching drops them — the failure NotesView already guards
// against on destruction, and the one every new caller rediscovers.
Item {
    id: root

    // The doc page being edited. Empty shows the placeholder.
    property string pageId: ""
    property string emptyText: ""

    // "edit" or "split".
    property string mode: "split"

    property bool _loading: false
    property bool _dirty: false

    function load() {
        root._loading = true;
        area.text = root.pageId.length > 0 ? AppController.docPageBody(root.pageId) : "";
        root._loading = false;
        root._dirty = false;
    }

    // Write now rather than in 250 ms. Called before anything that changes
    // which document is open, and on destruction.
    function flush() {
        if (!root._dirty || root.pageId.length === 0) return;
        saveTimer.stop();
        AppController.setDocPageBody(root.pageId, area.text);
        root._dirty = false;
    }

    onPageIdChanged: root.load()
    Component.onCompleted: root.load()
    Component.onDestruction: root.flush()

    Connections {
        target: Qt.application
        function onAboutToQuit() {
            root.flush();
            AppController.flushSave();
        }
    }

    // The body may change under us — an undo, a profile switch, an import.
    Connections {
        target: AppController.docPages
        function onDataChanged() {
            if (root._dirty || root.pageId.length === 0) return;
            const fresh = AppController.docPageBody(root.pageId);
            if (fresh !== area.text) root.load();
        }
        function onModelReset() { root.load() }
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: {
            if (root.pageId.length === 0) return;
            AppController.setDocPageBody(root.pageId, area.text);
            root._dirty = false;
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    Text {
        anchors.centerIn: parent
        visible: root.pageId.length === 0
        text: root.emptyText
        color: Theme.textDim
        font.pixelSize: 12
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.pageId.length > 0
        spacing: 0

        // Head: the title of the page, and how it is being shown.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            color: Theme.panel
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: Theme.border
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 10
                spacing: 8
                Text {
                    text: {
                        const m = AppController.docPages;
                        const r = m.roleOf("title");
                        const at = m.indexOfId(root.pageId);
                        return (at >= 0 && r >= 0) ? String(m.data(m.index(at, 0), r)) : "";
                    }
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    // Words, not characters: the number anybody writing a
                    // document actually wants.
                    text: I18n.t("docs.words").arg(area.text.trim().length === 0
                                                   ? 0
                                                   : area.text.trim().split(/\s+/).length)
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
                Repeater {
                    model: ["edit", "split"]
                    delegate: Rectangle {
                        required property var modelData
                        objectName: "docpage-mode-" + modelData
                        implicitWidth: 44; implicitHeight: 22
                        radius: 5
                        color: root.mode === modelData ? Theme.withAlpha(Theme.accent, 0.18)
                             : modeMA.containsMouse ? Theme.panel3 : "transparent"
                        border.color: root.mode === modelData ? Theme.accent : Theme.border
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: I18n.t("docs.mode." + modelData)
                            color: root.mode === modelData ? Theme.text : Theme.textDim
                            font.pixelSize: 9
                        }
                        MouseArea {
                            id: modeMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.mode = modelData
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            QQC.ScrollView {
                // Equal preferred widths and both filling: that is what splits
                // a RowLayout down the middle. Sizing one half to parent.width
                // instead leaves the other at zero, which looks exactly like
                // the preview failing to render.
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                clip: true

                QQC.TextArea {
                    id: area
                    objectName: "docpage-text"
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    leftPadding: 16; rightPadding: 16; topPadding: 12
                    background: Rectangle { color: Theme.bg }
                    onTextChanged: {
                        if (root._loading) return;
                        root._dirty = true;
                        saveTimer.restart();
                    }
                }
            }

            Rectangle {
                visible: root.mode === "split"
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: Theme.border
            }

            MdView {
                id: preview
                objectName: "docpage-preview"
                visible: root.mode === "split"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                document: previewDoc
            }
        }
    }

    MdDocument {
        id: previewDoc
        // The preview follows the text field rather than the stored body, so it
        // keeps up while typing instead of lagging by the debounce.
        text: area.text
        allowRemoteImages: false
        palette: ({
            "text": Theme.text,
            "dim": Theme.textDim,
            "link": Theme.accent,
            "code": Theme.text,
            "codeBackground": Theme.panel2,
            "highlightBackground": Theme.accentSoft,
            "mention": Theme.stProg,
            "ticket": Theme.accent,
            "tag": Theme.stReview,
            "math": Theme.p2
        })
    }
}
