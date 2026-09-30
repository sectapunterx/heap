import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp

// "Open this link?" for anything that is not plainly a web page.
//
// Links in a note, a doc page or a catalogue entry are written by someone else.
// http(s), mailto and heap:// open straight away; anything else (file:,
// ms-settings:, a program path) can start a program, so the reader sees it
// first. One dialog for every surface: the Docs catalogue used to refuse such
// a link with a toast while the notes preview asked, for the same URL.
QQC.Dialog {
    id: root
    objectName: "mdLinkConfirm"
    property string link: ""

    // Opens safe links directly, asks about the rest.
    function openLink(url) {
        if (!url) return;
        if (AppController.isSafeLink(url)) {
            Qt.openUrlExternally(url);
            return;
        }
        root.link = url;
        root.open();
    }

    modal: true
    parent: QQC.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(460, (parent ? parent.width : 460) - 32)
    padding: Theme.inset
    title: I18n.t("md.link.confirm.title")
    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }
    contentItem: ColumnLayout {
        spacing: Theme.spMd
        Text {
            Layout.fillWidth: true
            text: I18n.t("md.link.confirm.body")
            color: Theme.textMuted
            font.pixelSize: Theme.fsMd
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            text: root.link
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsMd
            wrapMode: Text.WrapAnywhere
        }
    }
    footer: RowLayout {
        spacing: Theme.spMd
        Item { Layout.fillWidth: true }
        PillButton {
            text: I18n.t("common.cancel")
            onClicked: root.close()
        }
        PillButton {
            objectName: "mdLinkConfirmOpen"
            text: I18n.t("md.link.confirm.open")
            danger: true
            onClicked: {
                root.close();
                Qt.openUrlExternally(root.link);
            }
        }
        Item { Layout.preferredWidth: Theme.spMd }
    }
}
