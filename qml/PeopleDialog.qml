pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// "Кому написать" in full (DG-002, sheet X/N-Oth-Archive-People): the people
// something is pending on, one of them open beside the list. It replaces the
// legacy right panel's people list; Today shows the short version and opens
// this one. You mark, lowkey only remembers: nothing is sent anywhere.
Dialog {
    id: root
    objectName: "people-dialog"
    modal: true
    Overlay.modal: ModalScrim {}
    focus: true
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    padding: Theme.inset
    width: Math.min(Theme.px(720), (parent ? parent.width : 800) - 2 * Theme.sp3xl)
    height: Math.min(Theme.px(520), (parent ? parent.height : 600) - 2 * Theme.sp3xl)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    signal editRequested(string id)
    signal addRequested()

    property string currentId: ""
    property int _rev: 0
    readonly property var current: root._rev >= 0 && root.currentId.length ? AppController.personById(root.currentId) : ({})

    function showFor(id) {
        root.currentId = id || "";
        root.open();
        // No one asked for: the first one is open (the index is re-set so
        // the delegate hears it even when it already was 0).
        if (!root.currentId.length && list.count > 0) { list.currentIndex = -1; list.currentIndex = 0; }
        list.forceActiveFocus();
    }

    Connections {
        target: AppController.people
        function onDataChanged() { root._rev++; }
        function onRowsRemoved() { root._rev++; }
        function onModelReset() { root._rev++; }
    }

    function _stateText(s) {
        return s && s !== "idle" ? I18n.t("people.state." + s + ".tag").toLowerCase() : "";
    }

    header: DialogHeader { text: I18n.t("today.people") }
    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: Theme.spLg

        Text {
            Layout.fillWidth: true
            text: I18n.t("people.dialog.sub")
            color: Theme.textDim
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.sp2xl

            ColumnLayout {
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.spSm

                ListView {
                    id: list
                    objectName: "people-dialog-list"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.sp2xs
                    model: AppController.activePeople
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationEnabled: true
                    activeFocusOnTab: true
                    Accessible.role: Accessible.List
                    Keys.onReturnPressed: if (root.currentId.length) root.editRequested(root.currentId)

                    Text {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: I18n.t("people.empty")
                        color: Theme.textDim
                        font.pixelSize: Theme.fsSm
                    }

                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property string id
                        required property string name
                        required property string role
                        required property string question
                        required property var model
                        readonly property bool on: row.id === root.currentId
                        ListView.onIsCurrentItemChanged: if (ListView.isCurrentItem) root.currentId = row.id
                        width: ListView.view ? ListView.view.width : 0
                        implicitHeight: col.implicitHeight + 2 * Theme.spMd
                        radius: Theme.radiusMd
                        color: row.on ? Theme.panel2 : (hov.hovered ? Theme.withAlpha(Theme.text, 0.03) : "transparent")
                        Accessible.role: Accessible.ListItem
                        Accessible.name: row.name + (row.role.length ? ", " + row.role : "")
                        HoverHandler { id: hov }
                        ColumnLayout {
                            id: col
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spLg
                            spacing: Theme.sp2xs
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spSm
                                Text {
                                    text: row.name
                                    color: Theme.text
                                    font.pixelSize: Theme.fsMd
                                    font.weight: Theme.fwHeading
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.role
                                    elide: Text.ElideRight
                                    color: Theme.textDim
                                    font.pixelSize: Theme.fsXs
                                }
                                Text {
                                    text: root._stateText(row.model.state)
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fsXs
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: row.question.length > 0
                                text: row.question
                                elide: Text.ElideRight
                                color: Theme.textMuted
                                font.pixelSize: Theme.fsSm
                            }
                        }
                        ClickArea {
                            label: row.name
                            onActivated: { list.currentIndex = row.index; root.currentId = row.id; }
                        }
                    }
                }

                Text {
                    objectName: "people-dialog-add"
                    text: I18n.t("people.dialog.add") + (Style.keyHints ? " · " + AppController.shortcutText("person.new") : "")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fsSm
                    ClickArea {
                        label: I18n.t("people.dialog.add")
                        onActivated: root.addRequested()
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Theme.border
            }

            ColumnLayout {
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Theme.spSm
                visible: !!root.current.id

                Text {
                    text: root.current.name || ""
                    color: Theme.text
                    font.pixelSize: Theme.fsLg
                    font.weight: Theme.fwHeading
                }
                Text {
                    visible: text.length > 0
                    text: root.current.role || ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fsSm
                }
                Text {
                    Layout.topMargin: Theme.spMd
                    visible: (root.current.question || "").length > 0
                    text: I18n.t("people.dialog.ask")
                    color: Theme.textDim
                    font.pixelSize: Theme.fsXs
                }
                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.current.question || ""
                    wrapMode: Text.Wrap
                    color: Theme.text
                    font.pixelSize: Theme.fsSm
                }
                RowLayout {
                    Layout.topMargin: Theme.spMd
                    spacing: Theme.spSm
                    PillButton {
                        objectName: "people-dialog-wrote"
                        text: I18n.t("people.state.pinged.tag")
                        primary: root.current.state !== "pinged"
                        onClicked: AppController.setPersonState(root.currentId, "pinged")
                    }
                    PillButton {
                        objectName: "people-dialog-replied"
                        text: I18n.t("people.state.replied.tag")
                        onClicked: AppController.setPersonState(root.currentId, "replied")
                    }
                }
                RowLayout {
                    Layout.topMargin: Theme.spSm
                    spacing: Theme.spLg
                    Text {
                        objectName: "people-dialog-edit"
                        text: I18n.t("people.menu.edit")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        font.underline: true
                        ClickArea { label: I18n.t("people.menu.edit"); onActivated: root.editRequested(root.currentId) }
                    }
                    Text {
                        objectName: "people-dialog-dismiss"
                        text: I18n.t("people.menu.dismiss")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                        font.underline: true
                        ClickArea { label: I18n.t("people.menu.dismiss"); onActivated: AppController.setPersonState(root.currentId, "idle") }
                    }
                }
            }
        }
    }
}
