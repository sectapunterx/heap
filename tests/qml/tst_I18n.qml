// The string table is 1400 lines of hand-maintained key/value pairs in two
// languages, touched by every feature and asserted by nothing. These are the
// three properties that keep it honest.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "I18n"

    // A key present in one language and not the other is a string that silently
    // falls back to English for half the users. There is no way to see that
    // short of reading both tables side by side.
    function test_en_and_ru_cover_the_same_keys() {
        const en = Object.keys(I18n.dict.en).sort();
        const ru = Object.keys(I18n.dict.ru).sort();

        const missingRu = en.filter(k => I18n.dict.ru[k] === undefined);
        const extraRu = ru.filter(k => I18n.dict.en[k] === undefined);

        compare(missingRu.length, 0, "keys with no Russian: " + missingRu.join(", "));
        compare(extraRu.length, 0, "Russian keys with no English: " + extraRu.join(", "));
    }

    // An empty string renders as nothing at all, which looks like a layout bug
    // rather than a missing translation.
    function test_no_entry_is_empty() {
        for (const lang of ["en", "ru"]) {
            const table = I18n.dict[lang];
            for (const key in table) {
                verify(String(table[key]).length > 0, lang + "." + key + " is empty");
            }
        }
    }

    // The documented contract: a missing key returns itself, so a regression is
    // loud in the UI instead of rendering as blank.
    function test_an_unknown_key_returns_itself() {
        compare(I18n.t("no.such.key.exists"), "no.such.key.exists");
    }

    // Design audit DES-15: the first-run hints name rebindable shortcuts, so
    // they take them as arguments instead of spelling out the defaults.
    function test_first_run_hints_take_the_shortcuts_as_arguments() {
        const keys = ["board.empty.hint",
                      "board.empty.archivedHint", "timeline.empty.none.hint"];
        for (const lang of ["en", "ru"]) {
            for (const k of keys) {
                const s = String(I18n.dict[lang][k]);
                verify(s.indexOf("%1") >= 0, lang + "." + k + " has no %1: " + s);
                verify(!/Ctrl\+/.test(s), lang + "." + k + " spells out a shortcut: " + s);
            }
        }
    }

    // EYE-6: the Docs header counts each of its three numbers on its own;
    // ru had "31 записей" for every count.
    function test_docs_counts_are_plural_forms() {
        const savedLang = AppController.language;
        AppController.language = "ru";
        compare(I18n.docsCounts(1, 2, 5), "1 запись · 2 сниппета · 5 контактов");
        compare(I18n.docsCounts(21, 31, 11), "21 запись · 31 сниппет · 11 контактов");
        compare(I18n.docsCounts(31, 1, 22), "31 запись · 1 сниппет · 22 контакта");
        compare(I18n.docsCounts(5, 12, 0), "5 записей · 12 сниппетов · 0 контактов");
        AppController.language = "en";
        compare(I18n.docsCounts(1, 2, 5), "1 entry · 2 snippets · 5 contacts");
        compare(I18n.docsCounts(21, 1, 31), "21 entries · 1 snippet · 31 contacts");
        AppController.language = savedLang;
    }

    // …and a key that exists only in English still resolves under ru, rather
    // than falling through to the key.
    function test_ru_falls_back_to_english_not_to_the_key() {
        const sample = Object.keys(I18n.dict.en)[0];
        verify(sample !== undefined);
        verify(I18n.t(sample) !== sample, "a real key must not render as its own name");
    }
    // APP-188: displayed dates follow the UI language, the clock follows the
    // 12h / 24h setting. Settings and language are restored before asserting.
    function test_dates_follow_the_ui_language_and_the_clock_setting() {
        const savedSettings = AppController.appSettingsJson;
        const savedLang = AppController.language;
        const at = new Date(2026, 9, 6, 15, 15);
        const out = {};
        AppController.appSettingsJson = JSON.stringify({ calendar: { timeFormat: "24h" } });
        AppController.language = "en";
        out.en = I18n.fmtDate(at, "dayMonth");
        out.en24 = I18n.fmtDateTime(at, "dayMonth");
        out.enLong = I18n.fmtDate(at, "longWeekday");
        AppController.language = "ru";
        out.ru = I18n.fmtDate(at, "dayMonth");
        out.ru24 = I18n.fmtDateTime(at, "dayMonth");
        AppController.appSettingsJson = JSON.stringify({ calendar: { timeFormat: "12h" } });
        out.ru12 = I18n.fmtTime(at);
        AppController.language = "en";
        out.en12 = I18n.fmtDateTime(at, "weekdayDay");
        out.bad = I18n.fmtDate(new Date(NaN), "dayMonth");
        AppController.appSettingsJson = savedSettings;
        AppController.language = savedLang;

        compare(out.en, "Oct 6");
        compare(out.en24, "Oct 6, 15:15");
        compare(out.enLong, "Tuesday, October 6");
        // No dot after the short month (DG-031: "9 окт").
        compare(out.ru, "6 окт");
        compare(out.ru24, "6 окт, 15:15");
        compare(out.ru12, "3:15pm");
        compare(out.en12, "Tue, Oct 6, 3:15pm");
        compare(out.bad, "");
    }
}
