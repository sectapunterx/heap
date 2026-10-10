import QtQuick
import TodoCpp

// The OS keychain refused a tracker's sign-in (X/N-Err-Storage, R2-040). The
// token is only in memory now and would be gone after a restart, so the
// card asks: keep it in a file in the data folder (on Windows only this
// Windows account can read it back), or try the keychain again. Esc leaves
// it in memory for this session.
SmallDialog {
    id: root
    objectName: "keychain-card"
    property string _name: ""
    readonly property bool windows: Qt.platform.os === "windows"

    title: I18n.t("keychain.title").arg(root._name)
    fact: I18n.t(root.windows ? "keychain.fact.win" : "keychain.fact.other").arg(AppController.keychainName())
    onAccepted: { AppController.retryKeychain(); root.close(); }
    onClosed: AppController.dismissKeychainProblem()

    Connections {
        target: AppController
        function onKeychainProblemChanged() {
            const p = AppController.keychainProblem;
            if (p && p.provider) { root._name = p.name || p.provider; root.open(); }
        }
    }

    buttons: [
        PillButton {
            objectName: "keychain-file"
            text: I18n.t("keychain.file")
            onClicked: { AppController.keepSecretsInFile(); root.close(); }
        },
        PillButton {
            objectName: "keychain-retry"
            text: I18n.t("keychain.retry")
            primary: true
            solid: Style.fills
            onClicked: { AppController.retryKeychain(); root.close(); }
        }
    ]
}
