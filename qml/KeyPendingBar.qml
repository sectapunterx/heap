pragma ComponentBehavior: Bound
import QtQuick
import TodoCpp
import "KeyRules.js" as KeyRules

// "g …" at the bottom while the first key of a two-key sequence waits for
// its second (keymap.md rule 3): the prefix, then what can follow it here
// and what that does. Esc lets go; nothing happens after a second.
Rectangle {
    id: root

    // The waiting first key, PortableText ("G"); empty: hidden.
    property string pending: ""
    // function (id) → bool: whether an action is live where the person is.
    property var isLive: null

    // [{keys, label}] — the second keys that do something here. My views by
    // number fold into one "1…9".
    readonly property var items: {
        if (root.pending.length === 0) return [];
        const list = AppController.shortcuts;
        const head = root.pending + ", ";
        const out = [];
        const seen = {};
        let digits = [];
        let digitLabel = "";
        for (let i = 0; i < list.length; i++) {
            const seq = list[i].sequence || "";
            if (seq.indexOf(head) !== 0) continue;
            const live = root.isLive;
            if (live && !live(list[i].id)) continue;
            const second = seq.slice(head.length);
            if (/^[0-9]$/.test(second) && KeyRules.baseId(list[i].id).indexOf("savedView.") === 0) {
                digits.push(second);
                digitLabel = I18n.t("keys.pending.views");
                continue;
            }
            if (seen[second]) continue;
            seen[second] = true;
            out.push({ keys: AppController.keyText(second), label: list[i].label });
        }
        if (digits.length > 0) {
            digits.sort();
            out.push({ keys: digits.length > 1 ? digits[0] + "…" + digits[digits.length - 1] : digits[0], label: digitLabel });
        }
        return out;
    }

    visible: root.pending.length > 0
    implicitWidth: row.implicitWidth + 2 * Theme.spXl
    implicitHeight: row.implicitHeight + 2 * Theme.spMd
    width: implicitWidth
    height: implicitHeight
    radius: Theme.radiusLg
    color: Theme.panel
    border.color: Theme.border
    border.width: 1

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spXl
        Text {
            objectName: "key-pending-prefix"
            anchors.verticalCenter: parent.verticalCenter
            text: AppController.keyText(root.pending) + " …"
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsSm
            font.weight: Theme.fwTitle
        }
        Repeater {
            model: root.items
            delegate: Row {
                id: hint
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spSm
                KeyHint {
                    always: true
                    keys: hint.modelData.keys
                    color: Theme.text
                }
                Text {
                    text: hint.modelData.label
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.t("keys.pending.esc")
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsXs
        }
    }
}
