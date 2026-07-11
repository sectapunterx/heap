// Contract + smoke tests for qml/HelpContent.qml (the Settings -> Help page).
// HelpContent is a stateless presentational Item: a TOC whose rows emit
// anchorRequested(objectName), and one objectName'd HelpCard section per anchor.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "HelpContent"
    when: windowShown
    visible: true
    width: 500
    height: 500

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // Smoke: the whole tree instantiates — the inline HelpCard/H2/H3/Body/Hint/Kbd
    // components, the PillButton, and every Theme/I18n/AppController singleton
    // binding resolve. A removed property or renamed type returns null here.
    function test_smoke_load() {
        const hc = make('import TodoCpp; HelpContent {}');
        verify(hc !== null);
    }

    // Signal contract: anchorRequested carries the anchor objectName as a string,
    // which is exactly what SettingsView (onAnchorRequested -> _scrollToAnchor(name))
    // consumes. Emitted directly since the TOC rows expose no objectName to click.
    function test_anchor_requested_signal_carries_objectname() {
        const hc = make('import TodoCpp; HelpContent {}');
        let got = null;
        let count = 0;
        hc.anchorRequested.connect(function(name) { got = name; count++; });
        hc.anchorRequested("help-tweaks");
        compare(count, 1);
        compare(got, "help-tweaks");
    }

    // tocModel shape: a fixed list of {anchor, label} non-empty string pairs.
    function test_toc_model_shape() {
        const hc = make('import TodoCpp; HelpContent {}');
        const toc = hc.tocModel;
        verify(toc !== undefined && toc !== null, "tocModel missing");
        compare(toc.length, 15);
        for (let i = 0; i < toc.length; ++i) {
            verify(typeof toc[i].anchor === "string" && toc[i].anchor.length > 0,
                   "toc[" + i + "].anchor must be a non-empty string");
            verify(typeof toc[i].label === "string" && toc[i].label.length > 0,
                   "toc[" + i + "].label must be a non-empty string");
        }
    }

    // TOC anchors must be unique: a duplicate would make two rows scroll to the
    // same place (and duplicate objectNames make _findChildByName ambiguous).
    function test_toc_anchors_unique() {
        const hc = make('import TodoCpp; HelpContent {}');
        const toc = hc.tocModel;
        const seen = ({});
        for (let i = 0; i < toc.length; ++i) {
            const a = toc[i].anchor;
            verify(seen[a] === undefined, "duplicate TOC anchor: " + a);
            seen[a] = true;
        }
    }

    // The load-bearing cross-component contract: every TOC anchor must resolve to
    // a HelpCard whose objectName equals it. SettingsView._scrollToAnchor does
    // _findChildByName(bodyCol, anchor) and *silently no-ops* on a miss
    // (SettingsView.qml:611-612), so a missing section is an invisible dead link.
    // findChild here mirrors that recursive objectName search exactly.
    function test_every_toc_anchor_resolves_to_a_section() {
        const hc = make('import TodoCpp; HelpContent {}');
        const toc = hc.tocModel;
        for (let i = 0; i < toc.length; ++i) {
            const anchor = toc[i].anchor;
            const section = findChild(hc, anchor);
            verify(section !== null,
                   "TOC anchor '" + anchor + "' has no HelpCard with a matching objectName");
        }
    }
}
