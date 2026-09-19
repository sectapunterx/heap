#include "markdown/MdSourceMap.h"

#include <algorithm>

namespace heap::md {

namespace {

// UTF-16 code units a UTF-8 sequence starting with `lead` decodes to.
// Continuation bytes (10xxxxxx) contribute nothing; a 4-byte sequence becomes
// a surrogate pair and so counts twice.
inline int utf16UnitsForLeadByte(unsigned char lead) {
  if((lead & 0xC0) == 0x80) {
    return 0;
  }
  return (lead >= 0xF0) ? 2 : 1;
}

}  // namespace

MdSourceMap::MdSourceMap(const QString& text) : m_utf8(text.toUtf8()) {
  const int bytes = byteCount();
  const auto* p = reinterpret_cast<const unsigned char*>(m_utf8.constData());

  // CommonMark — and therefore md4c — ends a line at a line feed, a carriage
  // return, or a carriage return followed by a line feed. A lone carriage
  // return really does start a new line, and treating it as ordinary text
  // would put this map one line out of step with the parser: every block range
  // after it would be wrong. Line numbers are 0-based, and a terminator at the
  // very end closes the last line rather than opening an empty one.
  m_lineStartByte.append(0);
  m_lineStartUtf16.append(0);

  int utf16 = 0;
  for(int i = 0; i < bytes; ++i) {
    const bool isCr = p[i] == '\r';
    const bool isLf = p[i] == '\n';
    if(!isCr && !isLf) {
      utf16 += utf16UnitsForLeadByte(p[i]);
      continue;
    }

    const int terminator = (isCr && i + 1 < bytes && p[i + 1] == '\n') ? 2 : 1;
    m_lineEndByte.append(i);
    utf16 += terminator;
    i += terminator - 1;

    if(i + 1 < bytes) {
      m_lineStartByte.append(i + 1);
      m_lineStartUtf16.append(utf16);
    }
  }
  // The final line, if the document does not end with a terminator.
  if(m_lineEndByte.size() < m_lineStartByte.size()) {
    m_lineEndByte.append(bytes);
  }
  m_utf16Length = utf16;
}

int MdSourceMap::lineOfByte(int byte) const {
  if(byte <= 0) {
    return 0;
  }
  if(byte >= byteCount()) {
    return lineCount() - 1;
  }
  // First line whose start is greater than `byte`, minus one.
  const auto it = std::upper_bound(m_lineStartByte.cbegin(), m_lineStartByte.cend(), byte);
  return static_cast<int>(it - m_lineStartByte.cbegin()) - 1;
}

int MdSourceMap::lineStartByte(int line) const {
  if(line <= 0) {
    return 0;
  }
  if(line >= lineCount()) {
    return byteCount();
  }
  return m_lineStartByte.at(line);
}

int MdSourceMap::lineEndByte(int line) const {
  if(line < 0) {
    return 0;
  }
  if(line >= lineCount()) {
    return byteCount();
  }
  return m_lineEndByte.at(line);
}

QString MdSourceMap::lineTerminator(int line) const {
  if(line < 0 || line >= lineCount()) {
    return {};
  }
  const int from = m_lineEndByte.at(line);
  const int to = (line + 1 < lineCount()) ? m_lineStartByte.at(line + 1) : byteCount();
  return textForBytes(from, to);
}

int MdSourceMap::byteToUtf16(int byte) const {
  if(byte <= 0) {
    return 0;
  }
  if(byte >= byteCount()) {
    return m_utf16Length;
  }
  const auto* p = reinterpret_cast<const unsigned char*>(m_utf8.constData());

  // Snap onto a character boundary first. An offset pointing into the middle
  // of a multi-byte character has no UTF-16 position of its own, and counting
  // its lead byte would report the position *after* the character instead of
  // the character itself — which is how a caret ends up inside an emoji.
  while(byte > 0 && (p[byte] & 0xC0) == 0x80) {
    --byte;
  }

  const int line = lineOfByte(byte);
  const int from = m_lineStartByte.at(line);

  int units = m_lineStartUtf16.at(line);
  for(int i = from; i < byte; ++i) {
    units += utf16UnitsForLeadByte(p[i]);
  }
  return units;
}

int MdSourceMap::utf16ToByte(int pos) const {
  if(pos <= 0) {
    return 0;
  }
  if(pos >= m_utf16Length) {
    return byteCount();
  }
  const auto it = std::upper_bound(m_lineStartUtf16.cbegin(), m_lineStartUtf16.cend(), pos);
  const int line = static_cast<int>(it - m_lineStartUtf16.cbegin()) - 1;

  const auto* p = reinterpret_cast<const unsigned char*>(m_utf8.constData());
  int units = m_lineStartUtf16.at(line);
  int i = m_lineStartByte.at(line);
  const int bytes = byteCount();
  while(i < bytes && units < pos) {
    units += utf16UnitsForLeadByte(p[i]);
    ++i;
    // Land on the start of the next character, not inside it.
    while(i < bytes && (p[i] & 0xC0) == 0x80) {
      ++i;
    }
  }
  return i;
}

QString MdSourceMap::textForBytes(int startByte, int endByte) const {
  const int from = std::clamp(startByte, 0, byteCount());
  const int to = std::clamp(endByte, from, byteCount());
  return QString::fromUtf8(m_utf8.constData() + from, to - from);
}

QString MdSourceMap::lineText(int line) const {
  if(line < 0 || line >= lineCount()) {
    return {};
  }
  return textForBytes(lineStartByte(line), lineEndByte(line));
}

QString MdSourceMap::textForLines(int firstLine, int lastLine) const {
  const int first = std::clamp(firstLine, 0, std::max(lineCount() - 1, 0));
  const int last = std::clamp(lastLine, first, std::max(lineCount() - 1, 0));
  return textForBytes(lineStartByte(first), lineEndByte(last));
}

bool MdSourceMap::isBlankLine(int line) const {
  if(line < 0 || line >= lineCount()) {
    return true;
  }
  const int from = lineStartByte(line);
  const int to = lineEndByte(line);
  for(int i = from; i < to; ++i) {
    const char c = m_utf8.at(i);
    if(c != ' ' && c != '\t') {
      return false;
    }
  }
  return true;
}

}  // namespace heap::md
