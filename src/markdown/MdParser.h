#pragma once

#include "markdown/MdSourceMap.h"
#include "markdown/MdTypes.h"

namespace heap::md {

// Markdown source to an AST whose blocks carry the source lines they came from.
//
// The parsing itself is md4c's job. What lives here is the part md4c does not
// do: giving every block a source range. md4c reports offsets for text but not
// for block boundaries, and the notes editor needs those boundaries for almost
// everything — clicking a rendered block to put the caret in the right place,
// toggling a checkbox by rewriting one character, keeping two panes scrolled
// together, and swapping a block for its source in live preview.
//
// The ranges are derived in three steps:
//
//  1. A pre-pass holds frontmatter out of the parse by blanking it, so md4c
//     cannot mistake it for a setext heading or a paragraph. Offsets are
//     unaffected because the buffer keeps its length.
//  2. While parsing, every callback offset that points inside the input is
//     recorded as an anchor for the block being built. Synthesized text points
//     outside the buffer and is ignored.
//  3. Anchors give each top-level block a first and last line; the lines in
//     between and around are then assigned by a gap pass, so that the ranges
//     end up ordered, contiguous and covering the whole document.
//
// That last property is the one to hold onto: concatenating the source slices
// of the top-level blocks, joined by newlines, reproduces the document exactly.
// Tests assert it over every fixture, because an editor that writes back to
// the wrong range corrupts a note.

struct MdParseOptions {
  // Recognise a leading --- … --- block as frontmatter rather than markdown.
  bool frontmatter = true;
};

// Parse `src`. Never throws and never fails: malformed input yields whatever
// structure md4c could find, with the rest carried as Opaque blocks.
MdAst parse(const MdSourceMap& src, const MdParseOptions& options = {});

// Convenience for callers that only have text.
MdAst parse(const QString& markdown, const MdParseOptions& options = {});

}  // namespace heap::md
