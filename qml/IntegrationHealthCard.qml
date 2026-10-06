pragma ComponentBehavior: Bound

import QtQuick
import TodoCpp

// Settings → Integrations → Health (APP-164): for each connected tracker, when
// it last answered, what went wrong last in plain words, when its token runs
// out and how many issues the last pull carried. Read-only; the one action is
// the same "Sync now" the provider's own card has.
SettingsGroup {
    id: root
    objectName: "integration-health"
    title: I18n.t("health.title")
    description: I18n.t("health.hint")

    // Relative times ("5 min ago") are worked out in C++ against the clock at
    // the moment of reading; re-read when something is recorded and once a
    // minute so they do not go stale on screen.
    property int _tick: 0
    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root._tick++
    }
    Connections {
        target: AppController
        function onIntegrationHealthChanged() { root._tick++ }
        function onLanguageChanged() { root._tick++ }
        function onAppSettingsJsonChanged() { root._tick++ }
    }
    readonly property var healthRows: (root._tick, AppController.integrationHealth())

    SettingsRow {
        visible: root.healthRows.length === 0
        objectName: "health-empty"
        hint: I18n.t("health.none")
    }

    Repeater {
        model: root.healthRows
        delegate: SettingsRow {
            id: hrow
            required property var modelData
            objectName: "health-row-" + hrow.modelData.id
            label: hrow.modelData.name
            hintColor: hrow.modelData.failing ? Theme.warning : Theme.textMuted
            hint: {
                const d = hrow.modelData;
                const parts = [];
                parts.push(d.lastOk.length > 0 ? I18n.t("health.lastOk").arg(d.lastOk) : I18n.t("health.never"));
                if (d.items >= 0) parts.push(I18n.t("health.items").arg(d.items));
                if (d.expiry.length > 0) parts.push(d.expiry);
                if (d.offline) parts.push(I18n.t("settings.integrations.offline"));
                let line = parts.join(" · ");
                // Plain words first; the tracker's own answer after it, for
                // whoever wants the detail.
                if (d.failing)
                    line = d.error + " (" + d.errorAge + ")"
                         + (d.errorDetail.length > 0 ? "\n" + d.errorDetail : "") + "\n" + line;
                return line;
            }
            PillButton {
                objectName: "health-sync-" + hrow.modelData.id
                text: I18n.t("health.syncNow")
                enabled: !((IntegrationActivity.states[hrow.modelData.id] || ({})).busy || ({})).sync
                onClicked: {
                    IntegrationActivity.start(hrow.modelData.id, "sync");
                    AppController.syncProvider(hrow.modelData.id);
                }
            }
        }
    }
}
