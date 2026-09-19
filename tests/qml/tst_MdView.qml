// The rendered markdown view (qml/MdView.qml).
//
// The model is covered thoroughly in C++; what only a running scene can show
// is that each row type actually reaches its delegate and draws something.
// That is not hypothetical: the first version of this file declared its row
// components at the view level, where the delegate's id is out of scope, and
// every row rendered as an empty frame — correct model, nothing on screen.
// These tests fail if that happens again.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "MdView"
    when: windowShown
    visible: true
    width: 800
    height: 600

    MdDocument {
        id: doc
        palette: ({ "text": "#ffffff", "link": "#4488ff" })
    }

    // One view for the whole case. A ListView populates asynchronously, so
    // every assertion below polls rather than reading once — a fresh view per
    // test would as often be read before it had drawn anything.
    MdView {
        id: view
        anchors.fill: parent
        document: doc
    }

    function showMarkdown(markdown) {
        doc.text = markdown;
        doc.flush();
        wait(30);
    }

    // Delegates that draw something carry an objectName, so a test can ask
    // what the view actually built rather than what the model holds.
    function delegateNames() {
        const names = [];
        function walk(item) {
            if (!item)
                return;
            if (item.objectName && item.objectName.indexOf("md") === 0)
                names.push(item.objectName);
            const kids = item.children || [];
            for (let i = 0; i < kids.length; ++i)
                walk(kids[i]);
        }
        walk(view.contentItem);
        return names;
    }

    function builtOne(name) {
        return delegateNames().indexOf(name) >= 0;
    }

    function test_rows_reach_their_delegates_data() {
        return [
            { tag: "heading",   md: "# A heading\n",                     name: "mdHeading" },
            { tag: "paragraph", md: "just a paragraph\n",                name: "mdParagraph" },
            { tag: "code",      md: "```cpp\nint x = 1;\n```\n",         name: "mdCodeBody" },
            { tag: "table",     md: "| a | b |\n|---|---|\n| 1 | 2 |\n", name: "mdTable" },
            { tag: "rule",      md: "text\n\n---\n\nmore\n",             name: "mdRule" },
            { tag: "callout",   md: "> [!NOTE] Title\n> body\n",         name: "mdCallout" },
            { tag: "task",      md: "- [ ] a task\n",                    name: "mdTaskBox" },
            { tag: "bullet",    md: "- an item\n",                       name: "mdMarker" },
            { tag: "math",      md: "$$\nx^2\n$$\n",                     name: "mdMath" },
            { tag: "footnote",  md: "ref[^a]\n\n[^a]: the note\n",       name: "mdFootnoteDef" },
        ];
    }

    function test_rows_reach_their_delegates(data) {
        showMarkdown(data.md);
        verify(view.count > 0, "no rows for: " + data.md);
        tryVerify(function () { return builtOne(data.name); }, 3000,
                  "expected " + data.name + ", built: [" + delegateNames().join(", ") + "]");
    }

    // Text has to arrive in the delegate, not just a frame around it. An empty
    // string here is the exact symptom of the scoping bug described above.
    function test_text_reaches_the_delegate() {
        showMarkdown("# Visible heading\n\nA visible paragraph.\n");
        tryVerify(function () { return builtOne("mdHeading"); }, 3000);

        let found = "";
        function walk(item) {
            if (!item)
                return;
            if (item.objectName === "mdHeading")
                found = item.text;
            const kids = item.children || [];
            for (let i = 0; i < kids.length; ++i)
                walk(kids[i]);
        }
        walk(view.contentItem);
        verify(found.indexOf("Visible heading") >= 0, "heading delegate rendered: '" + found + "'");
    }

    // A remote image must not become an <img> the scene would fetch. heap
    // states it makes no network requests of its own, and an image in a note
    // would make one to a host the note's author picked.
    function test_remote_image_is_not_loaded_until_allowed() {
        doc.allowRemoteImages = false;
        showMarkdown("![alt](https://example.invalid/pixel.png)\n");
        tryVerify(function () { return builtOne("mdRemoteImage"); }, 3000,
                  "expected a placeholder, built: [" + delegateNames().join(", ") + "]");
        verify(!builtOne("mdImage"), "a remote image was loaded");
    }

    function test_local_image_renders() {
        showMarkdown("![alt](attachments/x.png)\n");
        tryVerify(function () { return builtOne("mdImage"); }, 3000,
                  "built: [" + delegateNames().join(", ") + "]");
    }

    // Rows map back to the lines they came from, which is what a click on a
    // rendered block uses to move the caret.
    function test_rows_map_back_to_source_lines() {
        showMarkdown("# One\n\npara\n\n- item\n");
        compare(doc.firstLineOfRow(0), 0);
        compare(doc.firstLineOfRow(1), 2);
        compare(doc.rowForLine(2), 1);
        compare(doc.lineForPosition(0), 0);
        compare(doc.positionForLine(2), 7);
    }

    // An empty note draws nothing a reader can see. The model still covers the
    // document — one blank row for the one empty line — so that every line maps
    // to something; that row has no delegate content of its own.
    function test_empty_document_draws_nothing() {
        showMarkdown("");
        wait(50);
        const names = delegateNames();
        verify(names.length === 0 || names.every(function (n) { return n === "mdBlank"; }),
               "built: [" + names.join(", ") + "]");
    }
}
