// Settings → Integrations → Health (APP-164). The rows come from
// AppController.integrationHealth(); the C++ side is covered by
// test_int_audit / test_sync_health. Here: the card renders, says so when
// nothing is connected, and has its strings in both languages.
import QtQuick
import QtQuick.Layouts
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "IntegrationHealth"
    when: windowShown
    visible: true
    width: 700
    height: 500

    ColumnLayout { id: host; width: 640 }

    Component {
        id: cardComp
        IntegrationHealthCard {}
    }

    function test_nothing_connected_says_so() {
        const prev = AppController.appSettingsJson;
        AppController.appSettingsJson = "{}";
        const card = cardComp.createObject(host);
        verify(card !== null);
        compare(card.healthRows.length, 0);
        verify(findChild(card, "health-empty").visible, "an empty page with no word why");
        card.destroy();
        AppController.appSettingsJson = prev;
    }

    function test_strings_exist_in_both_languages() {
        const keys = ["health.title", "health.hint", "health.none", "health.lastOk", "health.never",
                      "health.items", "health.syncNow", "palette.cmd.integrationsHealth"];
        for (let i = 0; i < keys.length; ++i) {
            verify(I18n.dict.en[keys[i]] !== undefined, keys[i] + " missing in en");
            verify(I18n.dict.ru[keys[i]] !== undefined, keys[i] + " missing in ru");
        }
    }
}
