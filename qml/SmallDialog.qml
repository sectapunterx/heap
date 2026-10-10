import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// The one small-dialog template (X-Dlg-Small): a question as the title, one
// line of fact under it, labelled fields, the buttons on the right. Enter is
// the main button (the dialog's `accepted`), Esc cancels.
//
//   SmallDialog {
//       title: I18n.t(...); fact: I18n.t(...)
//       DialogField { ... }
//       buttons: [ PillButton {...}, PillButton {...} ]
//   }
Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: 428
    anchors.centerIn: Overlay.overlay
    Overlay.modal: ModalScrim {}

    // A dim line above the title naming what happened ("Хранилище ключей
    // ОС недоступно", X/N-Err-Storage); none by default.
    property string eyebrow: ""
    property string title: ""
    property string fact: ""
    default property alias fields: fieldCol.data
    property alias buttons: btnRow.data
    signal accepted()

    background: ModalSurface {}

    contentItem: ColumnLayout {
        spacing: 0
        Text {
            objectName: "small-dialog-eyebrow"
            visible: root.eyebrow.length > 0
            Layout.topMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: root.eyebrow
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
            wrapMode: Text.Wrap
        }
        Text {
            objectName: "small-dialog-title"
            Layout.topMargin: root.eyebrow.length > 0 ? Theme.spMd : Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: root.title
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
            wrapMode: Text.Wrap
        }
        Text {
            objectName: "small-dialog-fact"
            visible: root.fact.length > 0
            Layout.topMargin: Theme.spXs
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            text: root.fact
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }
        ColumnLayout {
            id: fieldCol
            Layout.topMargin: Theme.spLg
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.fillWidth: true
            spacing: Theme.spMd
        }
        RowLayout {
            Layout.topMargin: Theme.spLg
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.bottomMargin: Theme.inset
            Layout.fillWidth: true
            spacing: Theme.spMd
            Item { Layout.fillWidth: true }
            RowLayout {
                id: btnRow
                spacing: Theme.spMd
            }
        }
    }
}
