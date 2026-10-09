// The words of the interface (APP-215, docs/GLOSSARY.md): one term for one
// thing. Ctrl K is "the command line", not "the palette"; Tweaks are gone
// into Settings → Appearance; a query is saved "as a view". Strings of the
// views that leave with heap 2 (welcome tour, side rail, Tweaks) are not
// checked — they go with their screens.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    name: "Glossary"

    readonly property var retired: ["welcome.", "siderail.", "tweaks."]
    // Says on purpose where the old things went.
    readonly property var allowed: ["settings.section.appearance.sub"]
    readonly property var banned: ({
        en: [/\bpalette\b/i, /\btweaks?\b/i, /\bsave view\b/i],
        ru: [/палитр/i, /твик/i, /сохранить вид\b/i]
    })

    function live(key) {
        if (allowed.indexOf(key) >= 0) return false;
        for (const p of retired) if (key.indexOf(p) === 0) return false;
        return true;
    }

    function test_banned_synonyms_do_not_come_back() {
        const bad = [];
        for (const lang of ["en", "ru"]) {
            const table = I18n.dict[lang];
            for (const key in table) {
                if (!live(key)) continue;
                for (const rx of banned[lang])
                    if (rx.test(String(table[key]))) bad.push(lang + ":" + key + " = " + table[key]);
            }
        }
        compare(bad.length, 0, "old terms in live strings:\n" + bad.join("\n"));
    }
}
