import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

// A hairline between groups of an AppMenu.
MenuSeparator {
    topPadding: Theme.spXs
    bottomPadding: Theme.spXs
    leftPadding: Theme.spSm
    rightPadding: Theme.spSm
    contentItem: Rectangle {
        implicitWidth: 160
        implicitHeight: 1
        color: Theme.border
    }
}
