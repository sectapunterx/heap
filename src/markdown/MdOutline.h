#pragma once

#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"

#include <QString>
#include <QStringList>
#include <QVector>

namespace heap::md {

// The document's structure, read off the AST: headings, the section each one
// owns, and the [[wiki-link]] graph between them.
//
// This replaces line-by-line regular expressions. A regex over lines cannot
// tell a heading from a line of shell script inside a fence, so `# comment` in
// a code block used to appear in the outline and answer a [[link]]. It also
// cannot see a setext heading, because that one is spread over two lines. The
// AST already knows both, and the block ranges already say which lines a
// heading owns, so the answers come out of data the parse produced anyway.

struct MdHeading {
  int level = 0;        // 1..6
  QString text;         // heading text, inline markup stripped
  int line = 0;         // 0-based line the heading sits on
  int utf16Offset = 0;  // position of the heading's first character
  // Lines this heading owns: itself, plus everything down to the next heading
  // of the same or higher rank. What a search hit or a fold needs.
  int sectionFirstLine = 0;
  int sectionLastLine = 0;
};

struct MdWikiRef {
  QString target;
  int line = 0;         // 0-based
  QString lineText;     // the whole line, trimmed, for a preview
  int utf16Offset = 0;  // where the [[ starts
};

// Headings in document order, including duplicates — the caller decides
// whether to de-duplicate, because an outline wants every heading while
// link autocomplete wants distinct targets.
QVector<MdHeading> outline(const MdSourceMap& src, const MdAst& ast);

// Every [[target]] in the document, in document order. References inside code
// spans and fenced blocks are skipped: text that happens to look like a link
// inside a shell snippet is not one.
QVector<MdWikiRef> wikiRefs(const MdSourceMap& src, const MdAst& ast);

// A searchable piece of a note: one per heading, plus a leading one for
// anything written above the first heading.
struct MdSection {
  QString title;  // heading path, e.g. "Release · Windows"
  QString body;   // the section's text, markup stripped
  int line = 0;   // 0-based line to jump to
};

// Split a document into sections for search.
//
// A note used to be one search entry holding the whole document, so a hit told
// the reader only that the word was somewhere in it. Per-heading sections give
// the palette a place to jump to and a snippet worth showing. Sections are
// capped so rebuilding the list stays cheap on a large note.
QVector<MdSection> searchSections(const QString& markdown, int bodyCap = 2000);

}  // namespace heap::md
