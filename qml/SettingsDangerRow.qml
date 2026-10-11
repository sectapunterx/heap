import QtQuick
import TodoCpp
import "ArmGuard.js" as ArmGuard

// A destructive settings row: the first press arms the button, the second
// within 3.5 s commits, and it disarms by itself.
SettingsRow {
    id: dangerRow
    property string buttonText: ""
    // Two-step: the first click arms, the second commits.
    property string confirmText: I18n.t("settings.data.wipe.confirm")
    property bool armed: false
    property real _armedAt: 0
    signal triggered()
    Timer { id: dangerDisarm; interval: 3500; onTriggered: dangerRow.armed = false }
    ActionButton {
        objectName: "danger-row-button"
        kind: "danger"
        armed: dangerRow.armed
        text: dangerRow.armed ? dangerRow.confirmText : dangerRow.buttonText
        onActivated: {
            if (!dangerRow.armed) { dangerRow.armed = true; dangerRow._armedAt = Date.now(); dangerDisarm.restart(); return; }
            if (ArmGuard.tooSoon(dangerRow._armedAt)) return;  // a double-click (IDIOT-SHELL-5)
            dangerRow.armed = false; dangerDisarm.stop(); dangerRow.triggered();
        }
    }
}
