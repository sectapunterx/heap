import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel
    height: 48

    property alias searchText: searchField.text
    signal newTaskRequested()

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 1; color: Theme.border
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16; anchors.rightMargin: 16
        spacing: 14

        // Brand
        RowLayout {
            spacing: 8
            Rectangle {
                width: 10; height: 10; radius: 3
                color: Theme.accent
                layer.enabled: true
            }
            Text {
                text: "todo<span style=\"color:" + Theme.textMuted + "\">·</span>cpp"
                textFormat: Text.RichText
                color: Theme.text
                font.family: Theme.fontMono
                font.weight: Font.DemiBold
                font.pixelSize: 13
            }
        }

        // Breadcrumbs — editable in place
        RowLayout {
            id: crumbs
            spacing: 4
            EditableCrumb {
                value: AppController.crumbProject
                placeholder: "project"
                bold: true
                onCommitted: (v) => AppController.crumbProject = v
            }
            CrumbSep {}
            // sprint segment — derived; not editable
            Text {
                text: AppController.sprintLabel()
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 12
            }
            CrumbSep {}
            EditableCrumb {
                value: AppController.crumbUser
                placeholder: "you"
                bold: true
                onCommitted: (v) => AppController.crumbUser = v
            }
        }

        Item { Layout.fillWidth: true }

        // Search
        Rectangle {
            Layout.preferredWidth: 280
            Layout.preferredHeight: 28
            radius: 6
            color: Theme.panel2
            border.color: Theme.border
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10; anchors.rightMargin: 6
                spacing: 4
                Text { text: "⌕"; color: Theme.textDim; font.pixelSize: 11 }
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Поиск задач, ID, branch…"
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    background: Item {}
                    selectByMouse: true
                }
                Rectangle {
                    radius: 4
                    border.color: Theme.border; border.width: 1
                    color: "transparent"
                    width: kbd.implicitWidth + 10; height: 16
                    Text {
                        id: kbd; anchors.centerIn: parent
                        text: "⌘K"; color: Theme.textDim
                        font.family: Theme.fontMono; font.pixelSize: 10
                    }
                }
            }
        }

        PillButton {
            text: "+ Task"
            primary: true
            onClicked: root.newTaskRequested()
        }
    }

    component CrumbSep: Text {
        text: "/"
        color: Theme.textMuted
        font.family: Theme.fontMono
        font.pixelSize: 12
    }

    component EditableCrumb: Item {
        id: ec
        property string value: ""
        property string placeholder: ""
        property bool bold: false
        property bool editing: false
        signal committed(string text)

        implicitWidth: editing ? Math.max(60, edit.implicitWidth + 12) : Math.max(20, label.implicitWidth + 6)
        implicitHeight: 22

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: hoverMA.containsMouse && !ec.editing ? Theme.panel2 : (ec.editing ? Theme.panel2 : "transparent")
            border.color: ec.editing ? Theme.accent : "transparent"
            border.width: ec.editing ? 1 : 0
        }

        Text {
            id: label
            anchors.centerIn: parent
            visible: !ec.editing
            text: ec.value.length > 0 ? ec.value : ec.placeholder
            color: ec.value.length > 0 ? Theme.text : Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.weight: ec.bold ? Font.Medium : Font.Normal
        }

        TextField {
            id: edit
            anchors.fill: parent
            anchors.leftMargin: 4; anchors.rightMargin: 4
            visible: ec.editing
            text: ec.value
            placeholderText: ec.placeholder
            color: Theme.text
            placeholderTextColor: Theme.textDim
            background: Item {}
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.weight: ec.bold ? Font.Medium : Font.Normal
            selectByMouse: true
            onAccepted: { ec.committed(edit.text.trim()); ec.editing = false }
            onActiveFocusChanged: if (!activeFocus && ec.editing) { ec.committed(edit.text.trim()); ec.editing = false }
            Keys.onEscapePressed: { edit.text = ec.value; ec.editing = false }
        }

        MouseArea {
            id: hoverMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            visible: !ec.editing
            onClicked: {
                ec.editing = true;
                edit.forceActiveFocus();
                edit.selectAll();
            }
        }
    }
}
