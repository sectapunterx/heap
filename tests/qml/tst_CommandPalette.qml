// CommandPalette: regression for the fuzzy-score proximity penalty pushing a
// genuine match below zero. _fuzzyScore documents "match -> >= 0, no match ->
// -1", but `score -= lastPos * 0.05` runs after the match check, so a single
// char first occurring at index >= 41 scored -0.05 and the caller's
// `if (score < 0) continue` dropped the entry even though the char is present.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "CommandPalette"
    when: windowShown
    visible: true
    width: 500
    height: 400

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    function test_smoke_load() {
        const cp = make('import TodoCpp; CommandPalette { }');
        verify(cp !== null);
    }

    // A present char must never score below 0, regardless of how late it matches.
    function test_fuzzy_late_single_char_not_negative() {
        const cp = make('import TodoCpp; CommandPalette { }');
        const late = "a".repeat(41) + "z";           // only 'z' at index 41
        verify(cp._fuzzyScore("z", late) >= 0, "a present char must score >= 0");
        // Boundary: index 40 lands exactly on 0 (survives even unpatched).
        compare(cp._fuzzyScore("z", "a".repeat(40) + "z"), 0.0);
        // A genuinely absent char must still return the negative no-match sentinel.
        verify(cp._fuzzyScore("z", "aaa") < 0, "absent char must score < 0");
    }

    // End-to-end: an entry whose only match for the query is a late single char
    // must survive _filterAndScore, not be dropped as if it were a no-match.
    function test_filter_keeps_late_single_char_entry() {
        const cp = make('import TodoCpp; CommandPalette { }');
        cp._entries = [{ kind: "task", label: "a".repeat(41) + "z", sub: "" }];
        const out = cp._filterAndScore("z");
        compare(out.length, 1, "an entry containing the query char must be kept");
    }
}
