// DocsEditor (qml/DocsEditor.qml): smoke-load of the Popup against the live
// TodoCpp module, its default property surface, the kind→width binding, and the
// full saved*/deleted* signal contract that DocsView (qml/DocsView.qml:1051)
// wires its saveDoc/saveSnippet/saveContact/saveSection handlers onto.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "DocsEditor"
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

    // Smoke: the Popup instantiates (Theme / PillButton / FieldLabel / FormField
    // / CodeHighlighter all resolve). A removed property or renamed type here
    // returns null.
    function test_smoke_load() {
        const de = make('import TodoCpp; DocsEditor { }');
        verify(de !== null);
    }

    // Public property defaults: the editor opens as a "doc" form, not-new,
    // modal, with empty ids/collections and an object draft.
    function test_default_properties() {
        const de = make('import TodoCpp; DocsEditor { }');
        compare(de.kind, "doc");
        compare(de.isNew, false);
        compare(de.sectionId, "");
        compare(de.originalRef, "");
        compare(de.idx, -1);
        compare(de.sections.length, 0);
        compare(de.contactPalette.length, 0);
        compare(de.accentPalette.length, 0);
        compare(de.docCustomFields.length, 0);
        compare(typeof de.draft, "object");
        compare(de.modal, true);
    }

    // width is bound to kind: the wide 700 layout is snippet-only; every other
    // kind is the 500 form. Exercises the ternary both ways as a live binding.
    function test_width_tracks_kind() {
        const de = make('import TodoCpp; DocsEditor { }');
        compare(de.width, 500);          // default kind === "doc"
        de.kind = "snippet";
        compare(de.width, 700);
        de.kind = "contact";
        compare(de.width, 500);
        de.kind = "section";
        compare(de.width, 500);
        de.kind = "doc";
        compare(de.width, 500);
    }

    // savedDoc carries the draft object (DocsView: onSavedDoc: (draft) => saveDoc(draft)).
    function test_signal_saved_doc() {
        const de = make('import TodoCpp; DocsEditor { }');
        let got = null;
        de.savedDoc.connect(function(d) { got = d; });
        de.savedDoc({ ref: "TS 36.331", title: "RRC" });
        verify(got !== null, "savedDoc must deliver its draft argument");
        compare(got.title, "RRC");
        compare(got.ref, "TS 36.331");
    }

    // deletedDoc is a bare notification (DocsView: () => deleteDoc(sectionId, originalRef)).
    function test_signal_deleted_doc() {
        const de = make('import TodoCpp; DocsEditor { }');
        let n = 0;
        de.deletedDoc.connect(function() { n++; });
        de.deletedDoc();
        compare(n, 1);
    }

    // savedSnippet carries the draft (DocsView pairs it with editor.idx).
    function test_signal_saved_snippet() {
        const de = make('import TodoCpp; DocsEditor { }');
        let got = null;
        de.savedSnippet.connect(function(d) { got = d; });
        de.savedSnippet({ title: "build", lang: "sh", code: "make" });
        verify(got !== null, "savedSnippet must deliver its draft argument");
        compare(got.title, "build");
        compare(got.lang, "sh");
    }

    function test_signal_deleted_snippet() {
        const de = make('import TodoCpp; DocsEditor { }');
        let n = 0;
        de.deletedSnippet.connect(function() { n++; });
        de.deletedSnippet();
        compare(n, 1);
    }

    // savedContact carries the draft (DocsView: onSavedContact: (draft) => saveContact(draft, idx)).
    function test_signal_saved_contact() {
        const de = make('import TodoCpp; DocsEditor { }');
        let got = null;
        de.savedContact.connect(function(d) { got = d; });
        de.savedContact({ name: "Ada", role: "PHY" });
        verify(got !== null, "savedContact must deliver its draft argument");
        compare(got.name, "Ada");
        compare(got.role, "PHY");
    }

    function test_signal_deleted_contact() {
        const de = make('import TodoCpp; DocsEditor { }');
        let n = 0;
        de.deletedContact.connect(function() { n++; });
        de.deletedContact();
        compare(n, 1);
    }

    // savedSection carries the draft (DocsView: onSavedSection: (draft) => saveSection(draft, sectionId)).
    function test_signal_saved_section() {
        const de = make('import TodoCpp; DocsEditor { }');
        let got = null;
        de.savedSection.connect(function(d) { got = d; });
        de.savedSection({ title: "3GPP", accent: "#3ba1ff" });
        verify(got !== null, "savedSection must deliver its draft argument");
        compare(got.title, "3GPP");
        compare(got.accent, "#3ba1ff");
    }

    function test_signal_deleted_section() {
        const de = make('import TodoCpp; DocsEditor { }');
        let n = 0;
        de.deletedSection.connect(function() { n++; });
        de.deletedSection();
        compare(n, 1);
    }
}
