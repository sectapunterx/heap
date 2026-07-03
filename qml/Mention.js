.pragma library

// Shared mention/reference commit helper for the Notes editor and the
// Quick-capture popups.
//
// Replaces the [start, end) span of a text editor (TextArea / TextField) with
// `insert`, using remove() + insert() rather than a wholesale
// `editor.text = …` reassignment.
//
// Why not `editor.text = before + insert + after`: assigning the whole `text`
// property resets the editor's caret to position 0 and fires onTextChanged
// synchronously mid-edit, so a cursorPosition set right afterwards does not
// stick — the user is dropped back to the start of the document. remove() +
// insert() edit the document in place and keep the caret at the edit point.
// (HEAP-65)
//
// Returns the resulting caret position (start + insert.length).
function commit(editor, start, end, insert) {
    editor.remove(start, end);
    editor.insert(start, insert);
    editor.cursorPosition = start + insert.length;
    return start + insert.length;
}
