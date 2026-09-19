#pragma once

#include "markdown/MdTypes.h"

#include <QHash>
#include <QString>

namespace heap::md {

// Inline content as Qt rich text.
//
// Qt Quick's Text and TextEdit render a useful subset of HTML, which is how a
// paragraph gets bold runs, links and inline code without a web engine. This
// turns one block's inline tree into that subset, and it is the only place
// that emits markup — everything else in the engine works on the AST.
//
// Two rules hold throughout. Every piece of document text is escaped, so a
// note containing "<script>" shows those characters rather than becoming
// markup: raw HTML in a note is displayed, never executed. And no tag is
// emitted that would make Qt fetch something over the network; see
// `allowRemoteImages`.

// Colours come from the QML theme rather than being baked in, so the rendered
// view matches the editor in both light and dark mode.
struct MdHtmlPalette {
  QString text;
  QString dim;
  QString link;
  QString code;
  QString codeBackground;
  QString highlightBackground;
  QString mention;
  QString ticket;
  QString tag;
  QString math;
};

struct MdHtmlOptions {
  MdHtmlPalette palette;

  // Remote images are off by default, and deliberately so. heap states that it
  // makes no network requests of its own; rendering <img src="http://…"> would
  // quietly make one on the author's behalf, to a host named by whoever wrote
  // the note, every time the note is opened. When this is false a remote image
  // renders as a link the reader can choose to follow.
  bool allowRemoteImages = false;

  // Numbers assigned to footnote ids, by first reference. Build it once per
  // document with footnoteNumbers() so every block agrees.
  QHash<QString, int> footnoteNumbers;
};

// Rich text for the inline content of one block.
QString inlineHtml(const MdAst& ast, const MdBlock& block, const MdHtmlOptions& options);

// Plain text of a block's inline content, markup dropped. For search snippets,
// accessibility labels and anywhere rich text would be noise.
QString inlinePlainText(const MdAst& ast, const MdBlock& block);

// Footnote ids in order of first reference, numbered from 1.
QHash<QString, int> footnoteNumbers(const MdAst& ast);

// Escapes text for inclusion in rich text. Exposed because block delegates
// build small pieces of markup of their own — a language badge, a callout
// title — from document text.
QString escapeHtml(const QString& text);

}  // namespace heap::md
