// Regression tests for the Notes / Quick-capture mention-commit helper.
//
// Locks HEAP-65: after picking an @person or #ticket suggestion the caret must
// land immediately after the inserted mention, NOT jump to the start of the
// document. The bug was a wholesale `editor.text = …` reassignment (resets the
// caret to 0); the fix edits in place via remove() + insert() in Mention.commit.
//
// Drives a real QtQuick.Controls TextArea so the test actually exercises the
// editor's caret behaviour, not just the string math.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml/Mention.js" as Mention

TestCase {
    name: "MentionCommit"
    when: windowShown

    TextArea { id: ed }

    function init() {
        ed.text = "";
        ed.cursorPosition = 0;
    }

    // @person mid-text: caret after the inserted name+space, not at 0.
    function test_caret_after_person_mention() {
        ed.text = "hi @jo there";
        ed.cursorPosition = 6;                 // right after "@jo"
        Mention.commit(ed, 3, 6, "@john_doe ");
        compare(ed.text, "hi @john_doe  there");
        compare(ed.cursorPosition, 13);        // 3 + len("@john_doe ") — NOT 0
        verify(ed.cursorPosition !== 0);
    }

    // Trigger at the very start of the document.
    function test_caret_at_start_trigger() {
        ed.text = "@bo";
        ed.cursorPosition = 3;
        Mention.commit(ed, 0, 3, "@bob ");
        compare(ed.text, "@bob ");
        compare(ed.cursorPosition, 5);
    }

    // #ticket reference in the middle keeps the trailing text intact.
    function test_ticket_ref_midtext() {
        ed.text = "see #he end";
        ed.cursorPosition = 7;                 // after "#he"
        Mention.commit(ed, 4, 7, "#HEAP-1 ");
        compare(ed.text, "see #HEAP-1  end");
        compare(ed.cursorPosition, 12);
    }

    // commit() returns the resulting caret position.
    function test_commit_returns_caret() {
        ed.text = "@a";
        ed.cursorPosition = 2;
        var caret = Mention.commit(ed, 0, 2, "@alice ");
        compare(caret, 7);
        compare(ed.cursorPosition, caret);
    }
}
