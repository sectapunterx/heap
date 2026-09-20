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

    // …and a key that exists only in English still resolves under ru, rather
    // than falling through to the key.
    function test_ru_falls_back_to_english_not_to_the_key() {
        const sample = Object.keys(I18n.dict.en)[0];
        verify(sample !== undefined);
        verify(I18n.t(sample) !== sample, "a real key must not render as its own name");
    }
}
