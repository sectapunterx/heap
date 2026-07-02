// First-run welcome. Modal that introduces the four headline features and
// dismisses via AppController.markWelcomeSeen() so it is shown exactly once.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: 560
    anchors.centerIn: Overlay.overlay

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.6)
    }

    function _finish() {
        AppController.markWelcomeSeen();
        root.close();
    }

    background: Rectangle {
        radius: 14
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    // One feature row: mark + title + description.
    component Feature: RowLayout {
        property string mark: ""
        property string title: ""
        property string desc: ""
        Layout.fillWidth: true
        spacing: 12
        Rectangle {
            Layout.alignment: Qt.AlignTop
            width: 30; height: 30; radius: 8
            color: Theme.panel2
            border.color: Theme.border; border.width: 1
            Text { anchors.centerIn: parent; text: parent.parent.mark; font.pixelSize: 15 }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: parent.parent.title; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text {
                text: parent.parent.desc; color: Theme.textMuted; font.pixelSize: 11
                wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 14

        ColumnLayout {
            Layout.topMargin: 22; Layout.leftMargin: 22; Layout.rightMargin: 22
            spacing: 3
            Text { text: I18n.t("welcome.title"); color: Theme.text; font.pixelSize: 20; font.weight: Font.Bold }
            Text {
                text: I18n.t("welcome.subtitle"); color: Theme.textMuted; font.pixelSize: 12
                wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
        }

        ColumnLayout {
            Layout.leftMargin: 22; Layout.rightMargin: 22; Layout.fillWidth: true
            spacing: 12
            Feature { mark: "▦"; title: I18n.t("welcome.board.title");    desc: I18n.t("welcome.board.desc") }
            Feature { mark: "◷"; title: I18n.t("welcome.calendar.title"); desc: I18n.t("welcome.calendar.desc") }
            Feature { mark: "⚡"; title: I18n.t("welcome.capture.title");  desc: I18n.t("welcome.capture.desc") }
            Feature { mark: "⌘"; title: I18n.t("welcome.palette.title");  desc: I18n.t("welcome.palette.desc") }
        }

        Rectangle {
            Layout.leftMargin: 22; Layout.rightMargin: 22; Layout.fillWidth: true
            radius: 8
            color: Theme.panel2
            border.color: Theme.border; border.width: 1
            implicitHeight: demoNote.implicitHeight + 20
            Text {
                id: demoNote
                anchors.fill: parent
                anchors.margins: 10
                text: I18n.t("welcome.demoNote")
                color: Theme.textMuted; font.pixelSize: 11
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }
        }

        RowLayout {
            Layout.leftMargin: 22; Layout.rightMargin: 22; Layout.bottomMargin: 20
            Item { Layout.fillWidth: true }
            PillButton {
                text: I18n.t("welcome.getStarted")
                primary: true
                onClicked: root._finish()
            }
        }
    }
}
