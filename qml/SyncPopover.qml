pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

// A click on the sync indicator (X/N-Ntf-Toasts, R2-048): every source and
// how it is doing — "2 мин назад · 41 тикет", "вход истёк в 12:10 · войти",
// "ждёт сети · 1 изменение в очереди", a calendar link's last fetch — and
// "Синхронизировать всё" with its key. Facts only; "войти" opens Settings.
Popup {
    id: root
    objectName: "sync-popover"
    padding: Theme.spSm
    width: Theme.px(340)
    background: PopupSurface {}
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    signal signInRequested(string providerId)

    property var sources: AppController.syncSources
    readonly property var calendars: AppController.calendarSubscriptions

    function openAt(anchor) {
        root.parent = anchor;
        root.x = 0;
        root.y = anchor.height + Theme.spXs;
        root.open();
    }
    function ago(iso) {
        const d = new Date(iso);
        if (!iso || isNaN(d.getTime())) return "";
        const min = Math.max(0, Math.round((Date.now() - d.getTime()) / 60000));
        if (min < 1) return I18n.t("know.ago.now");
        if (min < 60) return I18n.t("know.ago.min").arg(min);
        if (min < 24 * 60) return I18n.t("know.ago.hours").arg(Math.round(min / 60));
        return I18n.fmtDate(d, "dayMonth");
    }

    readonly property var rows: {
        const out = [];
        for (const s of root.sources || []) {
            let state = "ok", detail = "", action = "";
            if (s.offline || s.kind === "network") {
                state = "offline";
                detail = I18n.t("sync.src.offline") + ((s.waiting || 0) > 0 ? " · " + I18n.count(s.waiting, "sync.src.queued") : "");
            } else if (s.failing && s.kind === "auth") {
                state = "error";
                detail = s.failedAt ? I18n.t("sync.src.authExpired").arg(s.failedAt) : I18n.t("sync.src.authExpiredNoTime");
                action = "signIn";
            } else if (s.failing) {
                state = "error";
                detail = String(s.error || "");
            } else if (s.inFlight) {
                state = "syncing";
                detail = I18n.t("sync.src.syncing");
            } else if (s.lastOk) {
                detail = String(s.lastOk) + ((s.items || 0) >= 0 && s.items !== undefined && s.items >= 0
                                             ? " · " + I18n.count(s.items, "sync.src.tickets") : "");
            } else {
                state = "never";
                detail = I18n.t("sync.src.never");
            }
            out.push({ id: s.id, name: s.name, state: state, detail: detail, action: action });
        }
        for (const c of root.calendars || []) {
            const err = String(c.error || "");
            out.push({ id: "", name: c.name || I18n.t("sync.src.calendar"),
                       state: err.length > 0 ? "error" : c.busy ? "syncing" : c.lastSync ? "ok" : "never",
                       detail: err.length > 0 ? err : "ICS" + (c.lastSync ? " · " + root.ago(c.lastSync) : ""),
                       action: "" });
        }
        return out;
    }

    contentItem: ColumnLayout {
        spacing: 0
        Repeater {
            model: root.rows
            delegate: Item {
                id: src
                required property var modelData
                required property int index
                objectName: "sync-popover-row-" + src.index
                Layout.fillWidth: true
                implicitHeight: Math.max(Theme.chipH + Theme.spXs, srcRow.implicitHeight + Theme.spMd)
                RowLayout {
                    id: srcRow
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spMd
                    anchors.rightMargin: Theme.spMd
                    spacing: Theme.spMd
                    Item {
                        implicitWidth: Theme.spLg
                        implicitHeight: Theme.spLg
                        Layout.alignment: Qt.AlignVCenter
                        id: srcMark
                        // Bold colours a dot (ok / error / running); quiet
                        // keeps a dot for ok and shapes for the rest.
                        readonly property bool filled: src.modelData.state === "ok"
                            || (Style.urgency && (src.modelData.state === "error" || src.modelData.state === "syncing"))
                        Rectangle {
                            visible: srcMark.filled
                            anchors.centerIn: parent
                            width: Theme.spSm; height: width; radius: width / 2
                            color: !Style.urgency ? Theme.textMuted
                                 : src.modelData.state === "error" ? Theme.danger
                                 : src.modelData.state === "syncing" ? Theme.warning : Theme.success
                        }
                        Icon {
                            visible: !srcMark.filled
                            anchors.centerIn: parent
                            size: Theme.px(10)
                            name: src.modelData.state === "offline" ? "pending"
                                : src.modelData.state === "syncing" ? "progress" : "ring"
                            color: !Style.urgency ? Theme.textMuted
                                 : src.modelData.state === "error" ? Theme.danger
                                 : src.modelData.state === "never" ? Theme.textMuted : Theme.warning
                        }
                    }
                    Text {
                        Layout.preferredWidth: Theme.px(80)
                        Layout.alignment: Qt.AlignVCenter
                        text: src.modelData.name
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSm
                        font.weight: Theme.fwTitle
                        elide: Text.ElideRight
                    }
                    Text {
                        objectName: "sync-popover-detail"
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: src.modelData.detail
                        textFormat: Text.PlainText
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsXs
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        id: signInT
                        visible: src.modelData.action === "signIn"
                        Layout.alignment: Qt.AlignVCenter
                        text: I18n.t("sync.src.signIn")
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsXs
                        font.weight: Theme.fwTitle
                        font.underline: true
                        ClickArea {
                            anchors.margins: -Theme.spXs
                            label: signInT.text
                            showTip: false
                            onActivated: { root.close(); root.signInRequested(src.modelData.id); }
                        }
                    }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spXs
            implicitHeight: 1
            color: Theme.border
        }
        AppMenuItem {
            objectName: "sync-popover-all"
            Layout.fillWidth: true
            text: I18n.t("sync.all")
            shortcutId: "sync.all"
            onTriggered: { root.close(); AppController.syncNow(); }
        }
    }
}
