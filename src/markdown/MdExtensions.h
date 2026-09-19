#pragma once

#include "markdown/MdSourceMap.h"
#include "markdown/MdTypes.h"

namespace heap::md {

// Markdown that CommonMark does not define but engineering notes are written
// in anyway.
//
// None of this is in md4c, and none of it needs to be: each one is ordinary
// markdown that carries a convention on top. A callout is a block quote whose
// first line happens to start with "[!NOTE]". A footnote definition is a
// paragraph whose first line happens to start with "[^id]:". Display maths is
// a paragraph that happens to contain nothing but one maths span. Recognising
// them after the parse costs one walk over the blocks and, crucially, cannot
// break the source ranges: no block is added, removed or re-ordered, only
// re-labelled.
//
// Inline decorations — ==highlight==, @mention, #TICKET-1, #tag, [^ref] — are
// deliberately *not* done here. They change nothing about the document's
// structure, so they are applied where they matter, when inline content is
// turned into rich text. See MdHtml.
void applyExtensions(const MdSourceMap& src, MdAst* ast);

// True when a code block should be shown as a diagram rather than as code.
// Mermaid has no renderer on any platform heap ships to — QtWebEngine is not
// available for the MinGW build — so the block stays a code block and the UI
// only labels it. Keeping the test here means one place changes if that ever
// gains a real renderer.
bool isDiagramLanguage(const QString& language);

}  // namespace heap::md
