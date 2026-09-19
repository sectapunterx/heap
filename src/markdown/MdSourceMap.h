#pragma once

#include <QByteArray>
#include <QString>
#include <QVector>

namespace heap::md {

// The markdown source, held as UTF-8 alongside the index needed to talk about
// positions in it three different ways at once.
//
// Three coordinate systems meet in the notes editor and none of them can be
// dropped. md4c parses UTF-8 and reports positions as byte offsets, because
// its UTF-16 mode is Windows-only and heap builds on three platforms.
// QTextDocument and every Qt Quick text item count UTF-16 code units. The
// rendered view and the outline work in lines. Converting ad hoc at each call
// site is how off-by-one bugs get in, so the conversion lives here and the
// parser hands out only what this class produced.
//
// Immutable: build one per parse. A document with n lines costs two int arrays
// of n+1 entries on top of the UTF-8 copy.
//
// The input is assumed to be well-formed UTF-16, which is what QTextDocument
// and the clipboard produce. A string holding an unpaired surrogate is not
// valid Unicode and cannot survive the trip through UTF-8, so slices of it
// would not reproduce the original — nothing here tries to preserve that case.
class MdSourceMap {
 public:
  MdSourceMap() = default;
  explicit MdSourceMap(const QString& text);

  // ── The UTF-8 buffer md4c parses ────────────────────────────────
  const char* data() const {
    return m_utf8.constData();
  }

  int byteCount() const {
    return static_cast<int>(m_utf8.size());
  }

  bool isEmpty() const {
    return m_utf8.isEmpty();
  }

  // True when `byte` addresses a character of this buffer. md4c hands text
  // callbacks a pointer into the input for real source text but points
  // elsewhere for anything it synthesized (entities, the NUL replacement,
  // normalised line breaks), so this is the test that separates an offset
  // worth recording from one that would be nonsense.
  bool containsByte(int byte) const {
    return byte >= 0 && byte < byteCount();
  }

  // ── Lines ───────────────────────────────────────────────────────
  // Line numbers are 0-based. A trailing terminator does not open a new line,
  // so "a\n" is one line; an empty document has one empty line.
  //
  // A line ends at "\n", "\r\n" or a lone "\r" — the three CommonMark line
  // endings, which is what md4c counts too. Splitting on "\n" alone would put
  // this map one line out of step with the parser on any text containing a
  // bare carriage return, and every block range past it would be wrong.
  int lineCount() const {
    return static_cast<int>(m_lineStartByte.size());
  }

  // 0-based line holding `byte`. Clamped, so an out-of-range offset still
  // yields a usable line rather than undefined behaviour.
  int lineOfByte(int byte) const;

  int lineStartByte(int line) const;
  // Byte just past the line's last character, excluding its terminator.
  int lineEndByte(int line) const;
  // The line's terminator exactly as it appears: "\n", "\r\n", "\r", or empty
  // for a final line that has none. Callers that rejoin line ranges need this
  // to reproduce the document rather than normalising it.
  QString lineTerminator(int line) const;

  // ── Conversions ─────────────────────────────────────────────────
  // Byte offset to UTF-16 code-unit position, the unit QTextDocument and
  // QTextCursor use. A byte in the middle of a multi-byte character maps to
  // the position of the character that contains it.
  int byteToUtf16(int byte) const;
  int utf16ToByte(int pos) const;

  int utf16Length() const {
    return m_utf16Length;
  }

  // ── Slices ──────────────────────────────────────────────────────
  // Decoded text for a half-open byte range, clamped to the buffer.
  QString textForBytes(int startByte, int endByte) const;
  // A line without its terminator.
  QString lineText(int line) const;
  // Text of a closed line range: terminators between the lines are included
  // verbatim, the one after the last line is not. Concatenating every block's
  // slice followed by that block's final lineTerminator() reproduces the
  // document, which is the invariant the parser's partition guarantees.
  QString textForLines(int firstLine, int lastLine) const;

  // True when the line has no characters other than spaces and tabs. Blank
  // lines separate blocks, so the partition asks this constantly.
  bool isBlankLine(int line) const;

 private:
  QByteArray m_utf8;
  QVector<int> m_lineStartByte;   // byte offset of each line's first character
  QVector<int> m_lineEndByte;     // byte just past its last character
  QVector<int> m_lineStartUtf16;  // same lines, in UTF-16 code units
  int m_utf16Length = 0;
};

}  // namespace heap::md
