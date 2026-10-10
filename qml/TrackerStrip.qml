pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import TodoCpp

// Above the Tasks view (X/N-Err-Tracker, R2-035/036): one line per tracker
// problem that is not solved yet — what happened, what it means, one action,
// and × to put the line away until the problem changes. A toast says it
// once when it happens; this line stays. Below the lines, a tracker's first
// pull, while it runs: "загружаем ваши тикеты" with placeholder rows.
//
// Nothing here sends anything: the actions sign in (Settings), pull again,
// or open the log.
ColumnLayout {
    id: root
    objectName: "tracker-strip"
    spacing: Theme.spSm

    signal signInRequested(string providerId)
    signal logRequested()

    // Bound to the controller; a test can set it by hand.
    property var sources: AppController.syncSources
    // "<id>:<failedAtMs>" put away with ×; a new failure shows again.
    property var hidden: ({})

    readonly property var rows: {
        const out = [];
        const src = root.sources || [];
        let offline = false, waiting = 0, offlineKey = "";
        for (let i = 0; i < src.length; i++) {
            const s = src[i];
            if (s.offline || s.kind === "network") {
                offline = true;
                waiting += s.waiting || 0;
                offlineKey += s.id + ",";
                continue;
            }
            if (!s.failing) continue;
            const key = s.id + ":" + (s.failedAtMs || 0);
            if (root.hidden[key]) continue;
            if (s.kind === "auth") {
                out.push({ key: key, id: s.id, icon: "info", action: "signIn",
                           fact: s.failedAt ? I18n.t("trk.strip.auth").arg(s.name).arg(s.failedAt)
                                            : I18n.t("trk.strip.authNoTime").arg(s.name),
                           more: I18n.t("trk.strip.stale").arg(s.name),
                           actionText: I18n.t("trk.strip.signIn") });
            } else if (s.kind === "rateLimited") {
                out.push({ key: key, id: s.id, icon: "pending", action: "retry",
                           fact: I18n.t("trk.strip.rate").arg(s.name),
                           more: I18n.t("trk.strip.rateNext"),
                           actionText: I18n.t("trk.strip.retryNow") });
            } else {
                const e = String(s.error || "");
                out.push({ key: key, id: s.id, icon: "info", action: "retry",
                           fact: I18n.t("trk.strip.failed").arg(s.name)
                                 .arg(e.length > 0 ? e.charAt(0).toLowerCase() + e.slice(1) : ""),
                           more: I18n.t("trk.strip.stale").arg(s.name),
                           actionText: I18n.t("trk.strip.retry") });
            }
        }
        if (offline && !root.hidden["offline:" + offlineKey + waiting]) {
            out.push({ key: "offline:" + offlineKey + waiting, id: "", icon: "pending", action: "log",
                       fact: I18n.t("trk.strip.offline"),
                       more: waiting > 0 ? I18n.t("trk.strip.offlineWaiting").arg(waiting) : I18n.t("trk.strip.offlineSaved"),
                       actionText: I18n.t("trk.strip.log") });
        }
        return out;
    }
    // A tracker that has never answered and is pulling now (R2-036).
    readonly property var firstLoads: {
        const out = [];
        const src = root.sources || [];
        for (let i = 0; i < src.length; i++)
            if (src[i].inFlight && !src[i].everOk && !src[i].failing) out.push(src[i]);
        return out;
    }

    function hide(key) {
        const h = Object.assign({}, root.hidden);
        h[key] = true;
        root.hidden = h;
    }
    function act(row) {
        if (row.action === "signIn") root.signInRequested(row.id);
        else if (row.action === "retry") AppController.syncProvider(row.id);
        else if (row.action === "log") root.logRequested();
    }

    visible: rows.length > 0 || firstLoads.length > 0

    Repeater {
        model: root.rows
        delegate: Rectangle {
            id: line
            required property var modelData
            required property int index
            objectName: "tracker-strip-row-" + line.index
            Layout.fillWidth: true
            Layout.maximumWidth: Theme.px(900)
            implicitHeight: Math.max(Theme.chipH + Theme.spMd, lineRow.implicitHeight + 2 * Theme.spMd)
            radius: Theme.radiusMd
            color: "transparent"
            border.width: 1
            border.color: Theme.border
            RowLayout {
                id: lineRow
                anchors.fill: parent
                anchors.leftMargin: Theme.spLg
                anchors.rightMargin: Theme.spMd
                spacing: Theme.spMd
                Icon {
                    name: line.modelData.icon
                    color: line.modelData.icon === "info" && Style.urgency ? Theme.danger : Theme.text
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    objectName: "tracker-strip-fact"
                    text: line.modelData.fact
                    textFormat: Text.PlainText
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    font.weight: Theme.fwTitle
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    objectName: "tracker-strip-more"
                    Layout.fillWidth: true
                    text: line.modelData.more
                    textFormat: Text.PlainText
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    elide: Text.ElideRight
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    id: actT
                    objectName: "tracker-strip-action"
                    text: line.modelData.actionText
                    color: actCA.hovered ? Theme.textMuted : Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    font.weight: Theme.fwTitle
                    font.underline: true
                    Layout.alignment: Qt.AlignVCenter
                    ClickArea {
                        id: actCA
                        anchors.margins: -Theme.spXs
                        label: actT.text
                        showTip: false
                        onActivated: root.act(line.modelData)
                    }
                }
                Item {
                    implicitWidth: Theme.chipH * 0.8
                    implicitHeight: Theme.chipH * 0.8
                    Layout.alignment: Qt.AlignVCenter
                    Icon {
                        anchors.centerIn: parent
                        name: "close"
                        size: Theme.px(10)
                        color: hideCA.hovered ? Theme.text : Theme.textMuted
                    }
                    ClickArea {
                        id: hideCA
                        objectName: "tracker-strip-hide"
                        label: I18n.t("trk.strip.dismiss")
                        onActivated: root.hide(line.modelData.key)
                    }
                }
            }
        }
    }

    // A tracker's first pull: the panel stays while it runs (R2-036).
    Repeater {
        model: root.firstLoads
        delegate: Rectangle {
            id: panel
            required property var modelData
            objectName: "tracker-first-load"
            Layout.fillWidth: true
            Layout.maximumWidth: Theme.px(620)
            Layout.topMargin: Theme.spSm
            implicitHeight: panelCol.implicitHeight + 2 * Theme.spLg
            radius: Theme.radius
            color: "transparent"
            border.width: 1
            border.color: Theme.border
            ColumnLayout {
                id: panelCol
                anchors.fill: parent
                anchors.margins: Theme.spLg
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.spMd
                    spacing: Theme.spMd
                    Icon { name: "progress"; color: Style.urgency ? Theme.warning : Theme.text }
                    Text {
                        objectName: "tracker-first-load-title"
                        Layout.fillWidth: true
                        text: I18n.t("trk.first.title").arg(panel.modelData.name)
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSm
                        font.weight: Theme.fwTitle
                    }
                }
                Repeater {
                    model: 3
                    delegate: Item {
                        id: skel
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: Theme.chipH + Theme.spSm
                        Rectangle {
                            anchors.top: parent.top
                            width: parent.width; height: 1
                            color: Theme.border
                        }
                        Rectangle {
                            id: skelDot
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.statusRingSize; height: width; radius: width / 2
                            color: Theme.withAlpha(Theme.text, 0.08)
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: skelDot.right; anchors.leftMargin: Theme.spMd
                            width: parent.width * [0.55, 0.42, 0.62][skel.index]
                            height: Theme.spSm
                            radius: height / 2
                            color: Theme.withAlpha(Theme.text, 0.08)
                        }
                    }
                }
                Text {
                    Layout.topMargin: Theme.spMd
                    text: I18n.t("trk.first.note")
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                }
            }
        }
    }
}
