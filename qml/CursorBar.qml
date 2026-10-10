import QtQuick
import TodoCpp

// The lowkey underline motif (APP-280): a short lavender bar under the start
// of a label — the active sidebar section, the active note, the keyboard
// cursor on a card or row. Not a link underline (links are thin and grey)
// and not a box. Place it under the text it marks:
//
//   CursorBar { anchors.left: label.left; anchors.top: label.bottom; shown: isActive }
Rectangle {
    property bool shown: true
    // A tab or a settings section underlines its whole label instead.
    property bool full: false
    property Item target: null

    visible: shown
    width: full && target ? target.width : Theme.cursorBarW
    height: Theme.cursorBarH
    radius: height / 2
    color: Theme.focusRing
}
