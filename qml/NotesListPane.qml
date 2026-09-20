import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// The list of notes, beside the one being edited.
//
// Notes were one document per profile, so this pane had nothing to show and did
// not exist. Now that a profile holds many, the editor needs something that
// says which one is open and lets another be reached without a search.
//
// Pinned notes first, then folders, then loose notes — the order somebody
// scanning for a note actually uses, rather than the order they were created.
Rectangle {
    id: root

    property string filter: ""

    // Bumped by the model so the grouping rebuilds.
    property int rev: 0

    signal noteActivated(string id)

    color: Theme.panel
    implicitWidth: 240

    function _data(idx, name) {
        const m = AppController.notes;
        const r = m.roleOf(name);
        return r < 0 ? undefined : m.data(idx, r);
    }

    // Flat rows with a `kind`, so one ListView can draw both headers and notes
    // and the keyboard can walk them without a second structure to keep in step.
    function buildRows() {
        const _r = root.rev;
        const m = AppController.notes;
        const needle = root.filter.trim().toLowerCase();

        const pinned = [];
        const byFolder = ({});
        const loose = [];
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            const note = {
                id:      String(root._data(idx, "id")),
                title:   String(root._data(idx, "title") || ""),
                folder:  String(root._data(idx, "folder") || ""),
                pinned:  !!root._data(idx, "pinned"),
                excerpt: String(root._data(idx, "excerpt") || ""),
                updated: root._data(idx, "updated")
            };
            if (needle.length > 0) {
                const hay = (note.title + " " + note.excerpt + " " + note.folder).toLowerCase();
                if (hay.indexOf(needle) < 0) continue;
            }
            if (note.pinned) pinned.push(note);
            else if (note.folder.length > 0) {
                if (!byFolder[note.folder]) byFolder[note.folder] = [];
                byFolder[note.folder].push(note);
            } else loose.push(note);
        }

        const byTitle = function (a, b) {
            return a.title.toLowerCase() < b.title.toLowerCase() ? -1
                 : a.title.toLowerCase() > b.title.toLowerCase() ? 1 : 0;
        };
        pinned.sort(byTitle);
        loose.sort(byTitle);

        const rows = [];
        if (pinned.length > 0) {
            rows.push({ kind: "header", label: I18n.t("notes.pinned") });
            for (const n of pinned) rows.push({ kind: "note", note: n });
        }
        const folders = Object.keys(byFolder).sort();
        for (const f of folders) {
            rows.push({ kind: "header", label: f });
            byFolder[f].sort(byTitle);
            for (const n of byFolder[f]) rows.push({ kind: "note", note: n });
        }
        if (loose.length > 0) {
            if (rows.length > 0) rows.push({ kind: "header", label: I18n.t("notes.other") });
            for (const n of loose) rows.push({ kind: "note", note: n });
        }
        return rows;
    }
    readonly property var rows: buildRows()

    // The ids on screen, in order, so a caller can step through them.
    function visibleIds() {
        const out = [];
        for (let i = 0; i < root.rows.length; i++)
            if (root.rows[i].kind === "note") out.push(root.rows[i].note.id);
        return out;
    }

    // Open the note `delta` places from the open one. Headers are skipped
    // because they are not somewhere the selection can land.
    function step(delta) {
        const ids = root.visibleIds();
        if (ids.length === 0) return;
        const at = ids.indexOf(AppController.activeNoteId);
        const next = at < 0 ? 0 : Math.max(0, Math.min(ids.length - 1, at + delta));
        root.noteActivated(ids[next]);
    }

    Connections {
        target: AppController.notes
        function onRowsInserted() { root.rev++ }
        function onRowsRemoved()  { root.rev++ }
        function onDataChanged()  { root.rev++ }
        function onModelReset()   { root.rev++ }
    }

    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: 1; color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        anchors.rightMargin: 11
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: I18n.t("notes.all").toUpperCase()
                color: Theme.textMuted
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                Layout.fillWidth: true
            }
            Rectangle {
                objectName: "note-new"
                width: 22; height: 22; radius: 5
                color: newMA.containsMouse ? Theme.panel3 : Theme.panel2
                border.color: Theme.border; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.text
                    font.pixelSize: 14
                }
                MouseArea {
                    id: newMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.noteActivated(AppController.newNote())
                }
                QQC.ToolTip.visible: newMA.containsMouse
                QQC.ToolTip.delay: 500
                QQC.ToolTip.text: I18n.t("notes.newNote")
            }
        }

        QQC.TextField {
            id: filterField
            objectName: "note-filter"
            Layout.fillWidth: true
            placeholderText: I18n.t("notes.filter")
            placeholderTextColor: Theme.textDim
            color: Theme.text
            font.pixelSize: 11
            background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
            onTextChanged: root.filter = text
        }

        Text {
            visible: root.rows.length === 0
            Layout.fillWidth: true
            text: root.filter.length > 0 ? I18n.t("notes.noMatches") : I18n.t("notes.empty")
            color: Theme.textDim
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            objectName: "note-list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.rows
            QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

            delegate: Loader {
                required property var modelData
                width: list.width
                sourceComponent: modelData.kind === "header" ? headerRow : noteRow
                onLoaded: item.rowData = modelData
            }

            Component {
                id: headerRow
                Item {
                    property var rowData: ({})
                    height: 22
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.bottomMargin: 2
                        text: (rowData.label || "").toUpperCase()
                        color: Theme.textDim
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                        elide: Text.ElideRight
                    }
                }
            }

            Component {
                id: noteRow
                Rectangle {
                    id: row
                    property var rowData: ({})
                    readonly property var note: rowData.note || ({})
                    objectName: "note-row-" + (row.note.id || "")
                    height: 40
                    radius: 6
                    readonly property bool current: row.note.id === AppController.activeNoteId
                    color: row.current ? Theme.withAlpha(Theme.accent, 0.14)
                         : rowMA.containsMouse ? Theme.panel2 : "transparent"

                    Rectangle {
                        visible: row.current
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        anchors.margins: 6
                        width: 2; radius: 1
                        color: Theme.accent
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 8
                        anchors.topMargin: 4; anchors.bottomMargin: 4
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                text: row.note.title || ""
                                color: Theme.text
                                font.pixelSize: 11
                                font.weight: row.current ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            // A pin is only worth drawing where it is not
                            // already implied by the section it is under.
                            Text {
                                visible: row.note.pinned && row.rowData.inPinnedSection !== true
                                text: "•"
                                color: Theme.accent
                                font.pixelSize: 12
                            }
                        }
                        Text {
                            text: row.note.excerpt || ""
                            color: Theme.textDim
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            visible: (row.note.excerpt || "").length > 0
                        }
                    }

                    MouseArea {
                        id: rowMA
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) rowMenu.popup();
                            else root.noteActivated(row.note.id);
                        }
                    }

                    QQC.Menu {
                        id: rowMenu
                        QQC.MenuItem {
                            text: row.note.pinned ? I18n.t("notes.unpin") : I18n.t("notes.pin")
                            onTriggered: AppController.setNotePinned(row.note.id, !row.note.pinned)
                        }
                        QQC.MenuItem {
                            text: I18n.t("notes.rename")
                            onTriggered: renamePopup.openFor(row.note.id, row.note.title, row.note.folder)
                        }
                        QQC.MenuSeparator {}
                        QQC.MenuItem {
                            text: I18n.t("common.delete")
                            onTriggered: AppController.deleteNote(row.note.id)
                        }
                    }
                }
            }
        }
    }

    // Rename and re-file in one place: they are the same edit as far as the
    // reader is concerned — what this note is called and where it lives.
    QQC.Dialog {
        id: renamePopup
        objectName: "note-rename"
        property string noteId: ""
        modal: true
        anchors.centerIn: QQC.Overlay.overlay
        parent: QQC.Overlay.overlay
        padding: 18
        width: 380
        title: I18n.t("notes.rename")

        function openFor(id, title, folder) {
            renamePopup.noteId = id;
            titleField.text = title;
            folderField.text = folder;
            renamePopup.open();
            titleField.forceActiveFocus();
            titleField.selectAll();
        }

        function commit() {
            AppController.renameNote(renamePopup.noteId, titleField.text);
            AppController.moveNoteToFolder(renamePopup.noteId, folderField.text);
            renamePopup.close();
        }

        background: Rectangle {
            radius: 12
            color: Theme.panel
            border.color: Theme.borderStrong
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 8
            QQC.TextField {
                id: titleField
                objectName: "note-rename-title"
                Layout.fillWidth: true
                Layout.preferredWidth: 320
                color: Theme.text
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                onAccepted: renamePopup.commit()
            }
            QQC.TextField {
                id: folderField
                objectName: "note-rename-folder"
                Layout.fillWidth: true
                Layout.preferredWidth: 320
                placeholderText: I18n.t("notes.folderPlaceholder")
                placeholderTextColor: Theme.textDim
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: 11
                background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                onAccepted: renamePopup.commit()
            }
        }

        footer: RowLayout {
            spacing: 8
            Layout.margins: 14
            Item { Layout.fillWidth: true }
            PillButton { text: I18n.t("common.cancel"); onClicked: renamePopup.close() }
            PillButton { text: I18n.t("editor.btn.save"); primary: true; onClicked: renamePopup.commit() }
        }
    }
}
