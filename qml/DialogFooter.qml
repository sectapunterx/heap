import QtQuick
import QtQuick.Layouts
import TodoCpp

// The button row of a Controls Dialog: buttons pushed right, the dialog's
// inset around them (design audit DES-24). A RowLayout set as `footer` took
// no margins at all — `Layout.margins` does nothing there — so its buttons
// sat on the dialog's edge. Put the buttons inside, secondary first.
Item {
    default property alias buttons: row.data
    implicitHeight: row.implicitHeight + 2 * Theme.inset
    implicitWidth: row.implicitWidth + 2 * Theme.inset
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Theme.inset
        spacing: Theme.spMd
        Item { Layout.fillWidth: true }
    }
}
