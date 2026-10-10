// lowkey launch splash (N/X-Ntf-Focus "Запуск", R3-017): the wordmark and
// the version on the window background, nothing else. After an unclean exit
// (R3-018, "Запуск после сбоя") it says so under the wordmark and waits for
// an answer: "Посмотреть отчёт" opens the report form the person sends
// themselves, "Не отправлять" goes on. Nothing is ever sent from here.
import QtQuick
import TodoCpp

Item {
    id: root

    // 0..1 while the launch settles; drives the dismissal, not a bar.
    property real progress: 0.0
    property bool autoAnimate: true
    property int autoDuration: 1200
    readonly property string version: AppController.appVersion
    readonly property bool crashed: AppController.lastExitUnclean

    // The splash is done and may fade out.
    signal finished()
    // "Посмотреть отчёт".
    signal reportRequested()

    // Asked to leave: after a crash it stays until the card is answered.
    function dismiss() {
        if (!root.crashed) root.finished();
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.sp3xl, Theme.px(400))
        spacing: Theme.spMd

        BrandLogo {
            anchors.horizontalCenter: parent.horizontalCenter
            variant: "wordmark"
            theme: Theme.dark ? "dark" : "light"
            height: Theme.px(32)
        }
        Text {
            objectName: "splash-version"
            visible: !root.crashed
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.version
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
        }
        Text {
            objectName: "splash-crash-title"
            visible: root.crashed
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: I18n.t("crash.title")
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsMd
        }
        Text {
            objectName: "splash-crash-fact"
            visible: root.crashed
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.5
            text: {
                const t = AppController.lastSaveTime;
                const when = t && !isNaN(t.getTime()) ? I18n.fmtTime(t) : "";
                return (when ? I18n.t("crash.fact").arg(when) : I18n.t("crash.factNoTime")) + " " + I18n.t("crash.ask");
            }
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
        }
        Row {
            visible: root.crashed
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spSm
            Text {
                objectName: "splash-crash-report"
                text: I18n.t("crash.view")
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                font.underline: viewCA.hovered
                ClickArea {
                    id: viewCA
                    label: parent.text
                    onActivated: {
                        AppController.dismissUncleanExit();
                        root.finished();
                        root.reportRequested();
                    }
                }
            }
            Text { text: "·"; color: Theme.textDim; font.family: Theme.fontUi; font.pixelSize: Theme.fsSm }
            Text {
                objectName: "splash-crash-skip"
                text: I18n.t("crash.skip")
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                font.underline: skipCA.hovered
                ClickArea {
                    id: skipCA
                    label: parent.text
                    onActivated: {
                        AppController.dismissUncleanExit();
                        root.finished();
                    }
                }
            }
        }
    }

    // Enter / Esc answer the card from the keyboard: Esc = "Не отправлять".
    focus: root.crashed
    onCrashedChanged: if (root.crashed) root.forceActiveFocus()
    Component.onCompleted: if (root.crashed) root.forceActiveFocus()
    Keys.onEscapePressed: if (root.crashed) skipCA.activated()
    Keys.onReturnPressed: if (root.crashed) viewCA.activated()

    NumberAnimation on progress {
        running: root.autoAnimate
        from: 0; to: 1
        duration: root.autoDuration
        easing.type: Theme.easeEnter
        onFinished: root.dismiss()
    }
}
