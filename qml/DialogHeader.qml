import QtQuick
import TodoCpp

// The title of a Controls Dialog, drawn like the other popups' titles (design
// audit DES-24): Basic's default header set these three dialogs apart — its
// own size, weight and inset. Use as `header: DialogHeader { text: title }`.
Text {
    topPadding: Theme.inset
    leftPadding: Theme.inset
    rightPadding: Theme.inset
    color: Theme.text
    font.pixelSize: Theme.fsLg
    font.weight: Theme.fwHeading
    wrapMode: Text.Wrap
}
