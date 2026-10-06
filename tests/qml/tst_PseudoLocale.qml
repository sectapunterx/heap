// APP-189: the pseudo-locale stretches every string by 40 % and accents it,
// while placeholders, markup and line breaks survive, so .arg() and rich
// text work in it. It is off unless HEAP_LANG=pseudo.
import QtQuick
import QtTest
import TodoCpp
import "../../qml/Pseudo.js" as Pseudo

TestCase {
    name: "PseudoLocale"

    function test_strings_grow_by_at_least_forty_percent() {
        for (const s of ["Save", "Cancel", "Move left", "Settings", "Show done tasks in the timeline"]) {
            const p = Pseudo.pseudo(s);
            verify(p.length >= Math.ceil(s.length * 1.4), s + " → " + p);
            verify(p !== s);
            compare(p[0], "[");
            compare(p[p.length - 1], "]");
        }
    }

    function test_letters_are_accented_but_readable() {
        const p = Pseudo.pseudo("Settings");
        verify(p.indexOf("Šéţţíñĝš") === 1, p);
    }

    function test_placeholders_markup_and_breaks_survive() {
        const p = Pseudo.pseudo("Scale %1% of <b>all</b> &amp; more\nnext");
        verify(p.indexOf("%1") >= 0, p);
        verify(p.indexOf("<b>") >= 0 && p.indexOf("</b>") >= 0, p);
        verify(p.indexOf("&amp;") >= 0, p);
        verify(p.indexOf("\n") >= 0, p);
        compare(Pseudo.pseudo("%1 of %2").arg("a").arg("b").indexOf("a"), 1);
    }

    function test_empty_stays_empty() {
        compare(Pseudo.pseudo(""), "");
        compare(Pseudo.pseudo(undefined), "");
    }

    function test_off_by_default() {
        compare(AppController.pseudoLocale, false);
        compare(I18n.pseudo, false);
        verify(I18n.t("common.cancel").indexOf("[") !== 0);
    }
}
