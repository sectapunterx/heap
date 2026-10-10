pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// "Report a problem" (X/N-Err-Storage, R2-040): the person sends it. What
// goes in is chosen with two boxes and shown before anything leaves — the
// version, OS and today's log (on), the titles of the tasks in progress
// (off by default). Copy puts exactly the preview in the clipboard; "Open an
// issue on GitHub" opens a new-issue page with it. Nothing is sent by lowkey.
Popup {
    id: root
    objectName: "report-issue"
    modal: true
    focus: true
    padding: 0
    anchors.centerIn: Overlay.overlay
    parent: Overlay.overlay
    width: Math.min(456, (parent ? parent.width : 456) - 2 * Theme.sp2xl)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: ModalScrim {}
    background: ModalSurface {}

    signal noticeRequested(string text)
    property bool withDiagnostics: true
    property bool withTitles: false
    property string _diag: ""
    property string _titles: ""

    function showNow() {
        root.withDiagnostics = true;
        root.withTitles = false;
        root._diag = AppController.issueReportPreview();
        const day = AppController.todayData(AppController.today);
        const list = (day && day.inProgress) || [];
        root._titles = list.length > 0
            ? I18n.t("report.titlesHead") + "\n" + list.map(t => "- " + (t.title || t.id)).join("\n") : "";
        root.open();
    }
    readonly property string preview: {
        const parts = [];
        if (root.withDiagnostics && root._diag.length > 0) parts.push(root._diag);
        if (root.withTitles && root._titles.length > 0) parts.push(root._titles);
        return parts.join("\n\n");
    }

    contentItem: ColumnLayout {
        spacing: 0
        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("report.eyebrow")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spMd
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("report.title")
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spXs
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            text: I18n.t("report.includes")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
        }
        Check {
            objectName: "report-issue-diag"
            Layout.topMargin: Theme.spLg
            text: I18n.t("report.diag")
            checked: root.withDiagnostics
            onToggled: root.withDiagnostics = !root.withDiagnostics
        }
        Check {
            objectName: "report-issue-titles"
            Layout.topMargin: Theme.spSm
            text: I18n.t("report.titles")
            checked: root.withTitles
            onToggled: root.withTitles = !root.withTitles
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spLg
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            Layout.preferredHeight: Math.min(previewT.implicitHeight + 2 * Theme.spMd, Theme.px(150))
            radius: Theme.radiusMd
            color: "transparent"
            border.width: 1
            border.color: Theme.border
            clip: true
            Flickable {
                anchors.fill: parent
                anchors.margins: Theme.spMd
                contentHeight: previewT.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                ScrollBar.vertical: ThinScrollBar {}
                Text {
                    id: previewT
                    objectName: "report-issue-preview"
                    width: parent.width
                    text: root.preview.length > 0 ? root.preview : I18n.t("report.empty")
                    textFormat: Text.PlainText
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsXs
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spLg
            Layout.bottomMargin: Theme.inset
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
            spacing: Theme.spMd
            Item { Layout.fillWidth: true }
            PillButton {
                objectName: "report-issue-copy"
                text: I18n.t("report.copy")
                onClicked: {
                    AppController.copyToClipboard(root.preview);
                    root.noticeRequested(I18n.t("report.copied"));
                }
            }
            PillButton {
                objectName: "report-issue-open"
                text: I18n.t("report.open")
                primary: true
                solid: Style.fills
                onClicked: {
                    root.close();
                    AppController.openIssueReport(root.preview);
                }
            }
        }
    }

    component Check: Item {
        id: chk
        property string text: ""
        property bool checked: false
        signal toggled()
        Layout.fillWidth: true
        Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset
        implicitHeight: Math.max(box.height, label.implicitHeight)
        Rectangle {
            id: box
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.px(14); height: width
            radius: Theme.radiusSm
            color: chk.checked ? Theme.accent : "transparent"
            border.width: 1
            border.color: chk.checked ? Theme.accent : Theme.borderStrong
            Icon {
                anchors.centerIn: parent
                visible: chk.checked
                name: "check"
                size: Theme.px(10)
                color: Theme.bg
            }
        }
        Text {
            id: label
            anchors.left: box.right; anchors.leftMargin: Theme.spMd
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: chk.text
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            wrapMode: Text.Wrap
        }
        ClickArea {
            label: chk.text
            role: Accessible.CheckBox
            checked: chk.checked
            showTip: false
            onActivated: chk.toggled()
        }
    }
}
