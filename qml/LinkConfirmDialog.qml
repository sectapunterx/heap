import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// "Open the link in the browser?" (X-Dlg-Small, R3-076).
//
// Links in a note, a doc page or a task description are written by someone
// else. A web link asks once, with its address shown in full, so a link that
// reads "status" but points elsewhere is seen before the browser opens it;
// mailto and heap:// open straight away. Anything else (file:, ms-settings:, a
// program path) can start a program: the same dialog, with the warning and a
// red "Open anyway". One dialog for every surface.
QQC.Dialog {
    id: root
    objectName: "mdLinkConfirm"
    property string link: ""
    readonly property bool web: /^https?:\/\//i.test(root.link)

    // Opens mailto / heap:// directly, asks about the rest.
    function openLink(url) {
        if (!url) return;
        const isWeb = /^https?:\/\//i.test(url);
        if (!isWeb && AppController.isSafeLink(url)) {
            Qt.openUrlExternally(url);
            return;
        }
        root.link = url;
        root.open();
        openBtn.forceActiveFocus(Qt.TabFocusReason);
    }
    function go() {
        root.close();
        Qt.openUrlExternally(root.link);
    }

    modal: true
    QQC.Overlay.modal: ModalScrim {}
    parent: QQC.Overlay.overlay
    anchors.centerIn: parent
    // On the small-dialog template (X-Dlg-Small, R4-062): its width, the
    // fact right under the title, the buttons right under the field.
    width: Math.min(428, (parent ? parent.width : 428) - 32)
    padding: Theme.inset
    topPadding: Theme.spXs
    bottomPadding: 0
    title: root.web ? I18n.t("md.link.web.title") : I18n.t("md.link.confirm.title")
    header: DialogHeader { text: root.title }
    background: ModalSurface {}
    contentItem: ColumnLayout {
        spacing: Theme.spXl
        Text {
            Layout.fillWidth: true
            text: root.web ? I18n.t("md.link.web.body") : I18n.t("md.link.confirm.body")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
            lineHeightMode: Text.FixedHeight
            lineHeight: Math.round(Theme.fsMd * 1.45)
            wrapMode: Text.Wrap
        }
        DialogField {
            fieldName: "mdLinkAddress"
            label: I18n.t("md.link.address")
            mono: true
            text: root.link
            input.readOnly: true
            onAccepted: root.go()
        }
    }
    footer: DialogFooter {
        topGap: Theme.sp2xl
        PillButton {
            objectName: "mdLinkConfirmCopy"
            text: I18n.t("md.link.copy")
            onClicked: {
                AppController.copyToClipboard(root.link);
                AppController.toast(I18n.t("md.link.copied"));
                root.close();
            }
        }
        PillButton {
            id: openBtn
            objectName: "mdLinkConfirmOpen"
            text: root.web ? I18n.t("md.link.web.open") : I18n.t("md.link.confirm.open")
            primary: root.web
            danger: !root.web
            Keys.onReturnPressed: root.go()
            Keys.onEnterPressed: root.go()
            onClicked: root.go()
        }
    }
}
