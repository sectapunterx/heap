import QtQuick
import TodoCpp

// A destructive settings row: the first press arms the button, the second
// within 3.5 s commits, and it disarms by itself.
SettingsRow {
    id: dangerRow
    property string buttonText: ""
    // Two-step: the first click arms, the second commits.
    property string confirmText: I18n.t("settings.data.wipe.confirm")
    property bool armed: false
    signal triggered()
    Timer { id: dangerDisarm; interval: 3500; onTriggered: dangerRow.armed = false }
    ActionButton {
        objectName: "danger-row-button"
        kind: "danger"
        armed: dangerRow.armed
        text: dangerRow.armed ? dangerRow.confirmText : dangerRow.buttonText
        onActivated: {
            if (!dangerRow.armed) { dangerRow.armed = true; dangerDisarm.restart(); return; }
            dangerRow.armed = false; dangerDisarm.stop(); dangerRow.triggered();
        }
    }
}
