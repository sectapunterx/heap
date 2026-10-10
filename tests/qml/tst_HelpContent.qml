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
        compare(toc.length, 16);
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

    // UX-10: the whole guide reads in Russian when the app does, and flips
    // back without being rebuilt.
    function test_guide_follows_the_language() {
        const saved = AppController.language;
        const hc = make('import TodoCpp; HelpContent { width: 480 }');
        const texts = [];
        const walk = function (it) {
            if (!it) return;
            if (typeof it.text === "string" && it.contentWidth !== undefined) texts.push(it);
            const kids = it.children || [];
            for (let k = 0; k < kids.length; k++) walk(kids[k]);
        };
        walk(hc);
        const before = texts.length;
        verify(before > 100);
        AppController.language = "ru";
        texts.length = 0;
        walk(hc);
        const english = [];
        for (const t of texts) {
            const v = t.text;
            // Prose only: key chips, code and bare symbols are the same in both.
            if (v.length < 24 || /^[A-Za-z0-9+\-\/ .,]*$/.test(v) && v.indexOf(" ") < 0) continue;
            if (!/[А-Яа-яЁё]/.test(v)) english.push(v.slice(0, 60));
        }
        const tocRu = hc.tocModel[0].label;
        AppController.language = "en";
        const tocEn = hc.tocModel[0].label;
        AppController.language = saved;
        compare(english.length, 0, "English left in the Russian guide: " + english.join(" | "));
        verify(/[А-Яа-я]/.test(tocRu) && !/[А-Яа-я]/.test(tocEn), tocRu + " / " + tocEn);
    }

    // UX-30/34: key chips show the live bindings, and the views list names
    // Month and Archive (and no longer a "Day" view).
    function test_keys_are_live_and_views_are_current() {
        const hc = make('import TodoCpp; HelpContent {}');
        compare(hc.kbd("tweaks.open"), AppController.shortcutText("tweaks.open"));
        compare(hc.kbd("hotkeys.open"), AppController.shortcutText("hotkeys.open"));
        const views = hc.tocModel[0].label;
        verify(views.indexOf("Month") >= 0 || views.indexOf("месяц") >= 0, views);
        verify(views.indexOf("Archive") >= 0 || views.indexOf("архив") >= 0, views);
    }
}
