import QtQuick
import QtQuick.Controls.Basic
import TodoCpp

// A hairline between groups of an AppMenu. A hidden separator (a group that
// only exists for some items, e.g. tracker actions) collapses to zero height;
// a Menu's column keeps the slot of an invisible item otherwise.
MenuSeparator {
    height: visible ? implicitHeight : 0
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
