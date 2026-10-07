import QtQuick
import TodoCpp

// The dim layer behind every modal (APP-182). Use as
// `Overlay.modal: ModalScrim {}`; a modal without one fell back to the
// control style's grey, so dialogs dimmed the page by different amounts.
Rectangle {
    color: Theme.scrim
}
