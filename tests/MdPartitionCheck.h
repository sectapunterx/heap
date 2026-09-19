#pragma once

// The markdown parser's central invariant, shared by the parser tests and the
// fuzz run so the two can never drift apart.
//
// Every top-level block carries the range of source lines it came from, and
// those ranges must be ordered, contiguous and cover the whole document, with
// their slices re-concatenating to the original text. The editor writes back
// through these ranges — a checkbox toggle, a live-preview block edit, an
// outline jump — so a single off-by-one line silently corrupts a note.

#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"

#include <QString>
#include <QStringList>

namespace heap::md::test {

// A document rendered so it can be pasted back into a test verbatim. The
// escaping has to be unambiguous: a literal backslash followed by 'n' and an
// actual newline must not print the same way, or a fuzz failure sends you
// chasing a document that was never the failing one.
inline QString escape(const QString& text) {
  QString out;
  out.reserve(text.size() + 16);
  for(const QChar ch : text) {
    switch(ch.unicode()) {
      case u'\\':
        out += QStringLiteral("\\\\");
        break;
      case u'\n':
        out += QStringLiteral("\\n");
        break;
      case u'\r':
        out += QStringLiteral("\\r");
        break;
      case u'\t':
        out += QStringLiteral("\\t");
        break;
      default:
        if(ch.unicode() < 0x20) {
          out += QStringLiteral("\\x%1").arg(static_cast<uint>(ch.unicode()), 2, 16, QLatin1Char('0'));
        } else {
          out += ch;
        }
        break;
    }
  }
  return out;
}

// Human-readable dump of a document's lines and its top-level block ranges.
// Appended to every failure so a fuzz case explains itself without a rebuild.
inline QString describe(const QString& markdown) {
  const MdSourceMap src(markdown);
  const MdAst ast = parse(src);

  QString out = QStringLiteral("\nlines (%1):\n").arg(src.lineCount());
  for(int i = 0; i < src.lineCount(); ++i) {
    out += QStringLiteral("  %1%2 |%3|\n")
               .arg(i, 3)
               .arg(src.isBlankLine(i) ? QStringLiteral(" blank") : QStringLiteral("      "), escape(src.lineText(i)));
  }
  out += QStringLiteral("top-level blocks (%1):\n").arg(ast.topLevel().size());
  for(int i = 0; i < ast.topLevel().size(); ++i) {
    const MdBlock& block = ast.blocks.at(ast.topLevel().at(i));
    out += QStringLiteral("  %1 type=%2 lines=[%3,%4]\n")
               .arg(i, 3)
               .arg(static_cast<int>(block.type))
               .arg(block.span.firstLine)
               .arg(block.span.lastLine);
  }
  return out;
}

// Returns a description of the first violation, or an empty string when the
// partition holds.
inline QString checkPartition(const QString& markdown) {
  const MdSourceMap src(markdown);
  const MdAst ast = parse(src);
  if(!ast.isValid()) {
    return QStringLiteral("no root block");
  }

  const QVector<int>& top = ast.topLevel();
  if(top.isEmpty()) {
    return QStringLiteral("no top-level blocks");
  }

  int expectedLine = 0;
  QStringList slices;
  for(int i = 0; i < top.size(); ++i) {
    const MdSpan& span = ast.blocks.at(top.at(i)).span;
    if(!span.isValid()) {
      return QStringLiteral("block %1 has no span").arg(i);
    }
    if(span.firstLine != expectedLine) {
      return QStringLiteral("block %1 starts at line %2, expected %3%4")
          .arg(i)
          .arg(span.firstLine)
          .arg(expectedLine)
          .arg(describe(markdown));
    }
    // Each slice carries the terminator that actually followed its last line,
    // so a document mixing "\n", "\r\n" and a bare "\r" rebuilds byte for byte
    // instead of being normalised on the way back.
    slices << src.textForLines(span.firstLine, span.lastLine) + src.lineTerminator(span.lastLine);
    expectedLine = span.lastLine + 1;
  }
  if(expectedLine != src.lineCount()) {
    return QStringLiteral("partition ends at line %1, document has %2").arg(expectedLine).arg(src.lineCount());
  }

  const QString rebuilt = slices.join(QString());
  if(rebuilt != markdown) {
    return QStringLiteral("round-trip mismatch:\n--- got ---\n%1\n--- want ---\n%2%3")
        .arg(escape(rebuilt), escape(markdown), describe(markdown));
  }
  return {};
}

// Documents chosen because each has a real chance of breaking range
// assignment: structure that emits no offsets of its own, constructs that span
// blank lines, and text where byte and UTF-16 positions diverge.
inline QStringList partitionFixtures() {
  return {
      QStringLiteral(""),
      QStringLiteral("\n"),
      QStringLiteral("just one line"),
      QStringLiteral("a paragraph\n"),
      QStringLiteral("# Heading\n\nBody text.\n"),
      QStringLiteral("para one\n\npara two\n\npara three\n"),
      // Fenced code: neither fence line produces an offset of its own.
      QStringLiteral("```cpp\nint x = 1;\n```\n"),
      QStringLiteral("before\n\n```\ncode\n```\n\nafter\n"),
      QStringLiteral("```unterminated\nstill code\n"),
      QStringLiteral("```\n```\n"),
      // Setext headings: the underline carries no text.
      QStringLiteral("Title\n=====\n\nBody\n"),
      QStringLiteral("Subtitle\n--------\n"),
      // Thematic breaks produce no text callback at all.
      QStringLiteral("---\n"),
      QStringLiteral("a\n\n---\n\nb\n"),
      QStringLiteral("- one\n\n***\n\n- two\n"),
      // Tables: the delimiter row is structure, not content.
      QStringLiteral("| a | b |\n|---|---|\n| 1 | 2 |\n"),
      QStringLiteral("text\n\n| h |\n|---|\n| c |\n\nmore\n"),
      // Lists: tight, loose, nested, with a fence inside.
      QStringLiteral("- one\n- two\n- three\n"),
      QStringLiteral("- one\n\n- two\n\n- three\n"),
      QStringLiteral("1. first\n2. second\n"),
      QStringLiteral("- outer\n  - inner\n    - deepest\n"),
      QStringLiteral("- item\n\n  ```\n  code\n  ```\n\n- next\n"),
      QStringLiteral("- [ ] todo\n- [x] done\n"),
      QStringLiteral("- \n- \n"),
      // Quotes, including lazy continuation.
      QStringLiteral("> quoted\ncontinued lazily\n"),
      QStringLiteral("> outer\n> > inner\n"),
      QStringLiteral("> a\n\n> b\n"),
      // Link reference definitions emit no callbacks whatsoever.
      QStringLiteral("See [ref].\n\n[ref]: https://example.com\n"),
      QStringLiteral("[a]: /one\n[b]: /two\n\ntext with [a] and [b]\n"),
      // Frontmatter, held out of the parse.
      QStringLiteral("---\ntitle: note\n---\n\nBody.\n"),
      QStringLiteral("---\nunclosed frontmatter\n\nstill body\n"),
      // Non-ASCII, where byte offsets and UTF-16 positions diverge.
      QStringLiteral("# Заголовок\n\nтекст с emoji 🙂 и хвостом\n"),
      QStringLiteral("- [ ] задача с эмодзи 🙂\n"),
      // Indented code, HTML blocks, hard breaks.
      QStringLiteral("text\n\n    indented code\n    more code\n\ntext\n"),
      QStringLiteral("<div>\n  <p>html</p>\n</div>\n\nafter\n"),
      QStringLiteral("line one  \nline two\n"),
      // CRLF throughout.
      QStringLiteral("# Title\r\n\r\nBody line.\r\n"),
      // Blank-line runs.
      QStringLiteral("a\n\n\n\nb\n"),
      QStringLiteral("\n\n\n"),
      // Mixed everything.
      QStringLiteral("---\nk: v\n---\n\n# H\n\n> q\n\n- [ ] t\n\n```py\nx=1\n```\n\n| a |\n|---|\n| 1 |\n\n[r]: /x\n"),
  };
}

}  // namespace heap::md::test
