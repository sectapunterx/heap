#include "md4c.h"

#include "markdown/MdParser.h"

#include <algorithm>

namespace heap::md {

namespace {

// ── Pre-pass ────────────────────────────────────────────────────────
// Frontmatter is not markdown, but "---" is: left in the input it reads as a
// thematic break, or worse, turns the line above into a setext heading. It is
// blanked out of the buffer md4c sees — spaces, newlines kept — so every byte
// offset still means the same thing in the original source.

struct Reserved {
  BlockType type = BlockType::Opaque;
  int firstLine = -1;
  int lastLine = -1;
};

// Number of leading spaces/tabs on a line.
int indentOf(const MdSourceMap& src, int line) {
  const QString text = src.lineText(line);
  int i = 0;
  while(i < text.size() && (text.at(i) == u' ' || text.at(i) == u'\t')) {
    ++i;
  }
  return i;
}

// A frontmatter block is "---" on the very first line, closed by "---" or
// "..." on a later line. Unclosed means there is no frontmatter at all, which
// matches how editors that support it behave.
bool detectFrontmatter(const MdSourceMap& src, Reserved* out) {
  if(src.lineCount() < 2 || src.lineText(0).trimmed() != QStringLiteral("---")) {
    return false;
  }
  for(int line = 1; line < src.lineCount(); ++line) {
    const QString trimmed = src.lineText(line).trimmed();
    if(trimmed == QStringLiteral("---") || trimmed == QStringLiteral("...")) {
      out->type = BlockType::Frontmatter;
      out->firstLine = 0;
      out->lastLine = line;
      return true;
    }
  }
  return false;
}

// ── md4c glue ───────────────────────────────────────────────────────

BlockType mapBlock(MD_BLOCKTYPE type) {
  switch(type) {
    case MD_BLOCK_DOC:
      return BlockType::Document;
    case MD_BLOCK_QUOTE:
      return BlockType::Quote;
    case MD_BLOCK_UL:
      return BlockType::UnorderedList;
    case MD_BLOCK_OL:
      return BlockType::OrderedList;
    case MD_BLOCK_LI:
      return BlockType::ListItem;
    case MD_BLOCK_HR:
      return BlockType::ThematicBreak;
    case MD_BLOCK_H:
      return BlockType::Heading;
    case MD_BLOCK_CODE:
      return BlockType::CodeBlock;
    case MD_BLOCK_HTML:
      return BlockType::HtmlBlock;
    case MD_BLOCK_P:
      return BlockType::Paragraph;
    case MD_BLOCK_TABLE:
      return BlockType::Table;
    case MD_BLOCK_THEAD:
      return BlockType::TableHead;
    case MD_BLOCK_TBODY:
      return BlockType::TableBody;
    case MD_BLOCK_TR:
      return BlockType::TableRow;
    case MD_BLOCK_TH:
      return BlockType::TableHeaderCell;
    case MD_BLOCK_TD:
      return BlockType::TableCell;
  }
  return BlockType::Paragraph;
}

InlineType mapSpan(MD_SPANTYPE type) {
  switch(type) {
    case MD_SPAN_EM:
      return InlineType::Emphasis;
    case MD_SPAN_STRONG:
      return InlineType::Strong;
    case MD_SPAN_A:
      return InlineType::Link;
    case MD_SPAN_IMG:
      return InlineType::Image;
    case MD_SPAN_CODE:
      return InlineType::Code;
    case MD_SPAN_DEL:
      return InlineType::Strikethrough;
    case MD_SPAN_LATEXMATH:
      return InlineType::LatexMath;
    case MD_SPAN_LATEXMATH_DISPLAY:
      return InlineType::LatexMathDisplay;
    case MD_SPAN_WIKILINK:
      return InlineType::WikiLink;
    case MD_SPAN_U:
      return InlineType::Underline;
  }
  return InlineType::Text;
}

ColumnAlign mapAlign(MD_ALIGN align) {
  switch(align) {
    case MD_ALIGN_LEFT:
      return ColumnAlign::Left;
    case MD_ALIGN_CENTER:
      return ColumnAlign::Center;
    case MD_ALIGN_RIGHT:
      return ColumnAlign::Right;
    case MD_ALIGN_DEFAULT:
      break;
  }
  return ColumnAlign::Default;
}

// md4c hands attributes (link targets, fence info strings) back as a list of
// substrings so the caller can tell an entity from literal text. heap only
// needs the decoded string.
QString attributeText(const MD_ATTRIBUTE& attr) {
  if(attr.text == nullptr || attr.size == 0) {
    return {};
  }
  return QString::fromUtf8(attr.text, static_cast<int>(attr.size));
}

// One block while it is open: where its children go, and the extent of every
// source offset seen inside it.
struct OpenBlock {
  int index = -1;
  int minByte = -1;
  int maxByte = -1;
};

class Builder {
 public:
  Builder(const MdSourceMap& src, const MdParseOptions& options) : m_src(src), m_options(options) {
  }

  MdAst run();

  int onEnterBlock(MD_BLOCKTYPE type, void* detail);
  int onLeaveBlock(MD_BLOCKTYPE type, void* detail);
  int onEnterSpan(MD_SPANTYPE type, void* detail);
  int onLeaveSpan(MD_SPANTYPE type);
  int onText(MD_TEXTTYPE type, const MD_CHAR* text, MD_SIZE size);

 private:
  int addBlock(BlockType type);
  int addInline(InlineType type);

  // Record that [byteStart, byteEnd) of the source belongs to whatever block
  // is currently open. Offsets outside the buffer are ignored: md4c passes
  // pointers to its own storage for anything it synthesized.
  void anchor(int byteStart, int byteEnd);
  void anchorPointer(const MD_CHAR* text, MD_SIZE size);
  void anchorAttribute(const MD_ATTRIBUTE& attr);

  // Turn anchors into line ranges, then make the top level a total,
  // contiguous, ordered partition of the document.
  void assignSpans();
  void partitionTopLevel();
  MdSpan spanForLines(int firstLine, int lastLine) const;

  // Offset of `text` in the buffer md4c is parsing, or -1 when the pointer is
  // not into that buffer at all. md4c parses a copy of the source (the
  // pre-pass blanks frontmatter in it), so offsets must be taken against the
  // copy — it is the same length as the original, which is why they still mean
  // the same position in it.
  int offsetOf(const MD_CHAR* text) const;

  const MdSourceMap& m_src;
  MdParseOptions m_options;

  const char* m_base = nullptr;  // the buffer md4c parses
  int m_baseSize = 0;

  MdAst m_ast;
  QVector<OpenBlock> m_blockStack;
  QVector<int> m_spanStack;  // open inline nodes, innermost last
  int m_currentLeaf = -1;    // block whose inlines are being filled

  QVector<Reserved> m_reserved;
};

int Builder::addBlock(BlockType type) {
  MdBlock block;
  block.type = type;
  if(!m_blockStack.isEmpty()) {
    block.parent = m_blockStack.last().index;
  }
  m_ast.blocks.append(block);
  const int index = static_cast<int>(m_ast.blocks.size()) - 1;
  if(block.parent >= 0) {
    m_ast.blocks[block.parent].children.append(index);
  }
  return index;
}

int Builder::addInline(InlineType type) {
  MdInline node;
  node.type = type;
  if(!m_spanStack.isEmpty()) {
    node.parent = m_spanStack.last();
  }
  m_ast.inlines.append(node);
  const int index = static_cast<int>(m_ast.inlines.size()) - 1;
  if(node.parent >= 0) {
    m_ast.inlines[node.parent].children.append(index);
  } else if(m_currentLeaf >= 0) {
    m_ast.blocks[m_currentLeaf].inlines.append(index);
  }
  return index;
}

void Builder::anchor(int byteStart, int byteEnd) {
  if(!m_src.containsByte(byteStart)) {
    return;
  }
  const int end = std::clamp(byteEnd, byteStart + 1, m_src.byteCount());
  for(OpenBlock& open : m_blockStack) {
    open.minByte = (open.minByte < 0) ? byteStart : std::min(open.minByte, byteStart);
    open.maxByte = std::max(open.maxByte, end);
  }
}

int Builder::offsetOf(const MD_CHAR* text) const {
  if(text == nullptr || m_base == nullptr || m_baseSize == 0) {
    return -1;
  }
  // Comparing unrelated pointers is only meaningful because md4c either hands
  // back a pointer into the buffer we gave it or one into its own storage;
  // the range check is what separates the two.
  if(text < m_base || text >= m_base + m_baseSize) {
    return -1;
  }
  return static_cast<int>(text - m_base);
}

void Builder::anchorPointer(const MD_CHAR* text, MD_SIZE size) {
  const int offset = offsetOf(text);
  if(offset < 0) {
    return;
  }
  anchor(offset, offset + static_cast<int>(size));
}

void Builder::anchorAttribute(const MD_ATTRIBUTE& attr) {
  anchorPointer(attr.text, attr.size);
}

int Builder::onEnterBlock(MD_BLOCKTYPE type, void* detail) {
  const int index = addBlock(mapBlock(type));
  m_blockStack.append(OpenBlock{index, -1, -1});
  MdBlock& block = m_ast.blocks[index];

  switch(type) {
    case MD_BLOCK_DOC:
      m_ast.root = index;
      break;
    case MD_BLOCK_H:
      if(detail != nullptr) {
        block.headingLevel = static_cast<int>(static_cast<MD_BLOCK_H_DETAIL*>(detail)->level);
      }
      break;
    case MD_BLOCK_CODE:
      if(detail != nullptr) {
        auto* code = static_cast<MD_BLOCK_CODE_DETAIL*>(detail);
        block.fenced = code->fence_char != 0;
        block.codeLanguage = attributeText(code->lang).trimmed();
        // The info string is real source text, so it pins the opening fence.
        anchorAttribute(code->lang);
      }
      break;
    case MD_BLOCK_UL:
      if(detail != nullptr) {
        auto* list = static_cast<MD_BLOCK_UL_DETAIL*>(detail);
        block.tight = list->is_tight != 0;
        block.listMark = QChar(list->mark);
      }
      break;
    case MD_BLOCK_OL:
      if(detail != nullptr) {
        auto* list = static_cast<MD_BLOCK_OL_DETAIL*>(detail);
        block.tight = list->is_tight != 0;
        block.listStart = static_cast<int>(list->start);
        block.listMark = QChar(list->mark_delimiter);
      }
      break;
    case MD_BLOCK_LI:
      if(detail != nullptr) {
        auto* item = static_cast<MD_BLOCK_LI_DETAIL*>(detail);
        block.isTask = item->is_task != 0;
        if(block.isTask) {
          block.taskMark = QChar(item->task_mark);
          block.taskMarkByte = static_cast<int>(item->task_mark_offset);
          // The checkbox character is the only offset md4c gives for a list
          // item, and the one a click needs to rewrite.
          anchor(block.taskMarkByte, block.taskMarkByte + 1);
        }
      }
      break;
    case MD_BLOCK_TABLE:
      if(detail != nullptr) {
        block.columnCount = static_cast<int>(static_cast<MD_BLOCK_TABLE_DETAIL*>(detail)->col_count);
      }
      break;
    case MD_BLOCK_TH:
    case MD_BLOCK_TD:
      if(detail != nullptr) {
        block.align = mapAlign(static_cast<MD_BLOCK_TD_DETAIL*>(detail)->align);
      }
      break;
    default:
      break;
  }

  // Leaf blocks collect inline content; containers never do.
  switch(type) {
    case MD_BLOCK_H:
    case MD_BLOCK_CODE:
    case MD_BLOCK_HTML:
    case MD_BLOCK_P:
    case MD_BLOCK_TH:
    case MD_BLOCK_TD:
      m_currentLeaf = index;
      m_spanStack.clear();
      break;
    default:
      break;
  }
  return 0;
}

int Builder::onLeaveBlock(MD_BLOCKTYPE type, void* /*detail*/) {
  if(m_blockStack.isEmpty()) {
    return 0;
  }
  const OpenBlock closed = m_blockStack.takeLast();
  MdBlock& block = m_ast.blocks[closed.index];
  block.span.byteStart = closed.minByte;
  block.span.byteEnd = closed.maxByte;

  switch(type) {
    case MD_BLOCK_H:
    case MD_BLOCK_CODE:
    case MD_BLOCK_HTML:
    case MD_BLOCK_P:
    case MD_BLOCK_TH:
    case MD_BLOCK_TD:
      m_currentLeaf = -1;
      m_spanStack.clear();
      break;
    default:
      break;
  }
  return 0;
}

int Builder::onEnterSpan(MD_SPANTYPE type, void* detail) {
  const int index = addInline(mapSpan(type));
  m_spanStack.append(index);
  MdInline& node = m_ast.inlines[index];

  switch(type) {
    case MD_SPAN_A:
    case MD_SPAN_IMG:
      if(detail != nullptr) {
        auto* link = static_cast<MD_SPAN_A_DETAIL*>(detail);
        node.href = attributeText(link->href);
        node.title = attributeText(link->title);
        // Deliberately not anchored: for a reference link the target text
        // lives in the definition somewhere else in the document, and
        // recording it would stretch this block's range over both.
      }
      break;
    case MD_SPAN_WIKILINK:
      if(detail != nullptr) {
        auto* wiki = static_cast<MD_SPAN_WIKILINK_DETAIL*>(detail);
        node.href = attributeText(wiki->target);
        anchorAttribute(wiki->target);
      }
      break;
    default:
      break;
  }
  return 0;
}

int Builder::onLeaveSpan(MD_SPANTYPE /*type*/) {
  if(!m_spanStack.isEmpty()) {
    m_spanStack.removeLast();
  }
  return 0;
}

int Builder::onText(MD_TEXTTYPE type, const MD_CHAR* text, MD_SIZE size) {
  InlineType kind = InlineType::Text;
  switch(type) {
    case MD_TEXT_BR:
      kind = InlineType::HardBreak;
      break;
    case MD_TEXT_SOFTBR:
      kind = InlineType::SoftBreak;
      break;
    case MD_TEXT_HTML:
      kind = InlineType::HtmlInline;
      break;
    default:
      break;
  }

  const int index = addInline(kind);
  MdInline& node = m_ast.inlines[index];
  if(kind == InlineType::Text || kind == InlineType::HtmlInline) {
    node.text = QString::fromUtf8(text, static_cast<int>(size));
  }

  // Only real source text carries a span. An entity, a NUL replacement or a
  // normalised soft break points into md4c's own storage.
  const int offset = offsetOf(text);
  if(offset >= 0) {
    const int end = std::min(offset + static_cast<int>(size), m_src.byteCount());
    node.span = spanForLines(m_src.lineOfByte(offset), m_src.lineOfByte(std::max(end - 1, offset)));
    node.span.byteStart = offset;
    node.span.byteEnd = end;
  }
  anchorPointer(text, size);
  return 0;
}

MdSpan Builder::spanForLines(int firstLine, int lastLine) const {
  MdSpan span;
  span.firstLine = firstLine;
  span.lastLine = std::max(firstLine, lastLine);
  span.byteStart = m_src.lineStartByte(span.firstLine);
  span.byteEnd = m_src.lineEndByte(span.lastLine);
  return span;
}

void Builder::assignSpans() {
  // Byte extents became line ranges; nested blocks inherit from their anchors
  // just like top-level ones. The top level is then squared up so its ranges
  // tile the document.
  for(MdBlock& block : m_ast.blocks) {
    if(block.type == BlockType::Document) {
      continue;
    }
    if(block.span.byteStart >= 0) {
      block.span.firstLine = m_src.lineOfByte(block.span.byteStart);
      block.span.lastLine = m_src.lineOfByte(std::max(block.span.byteEnd - 1, block.span.byteStart));
    }
  }
  partitionTopLevel();
}

void Builder::partitionTopLevel() {
  if(!m_ast.isValid()) {
    return;
  }
  const int lines = m_src.lineCount();

  // Reserved regions (frontmatter) are blocks in their own right and sit
  // before anything md4c produced.
  QVector<int> order;
  order.reserve(m_ast.blocks.at(m_ast.root).children.size() + m_reserved.size());
  for(const Reserved& reserved : m_reserved) {
    MdBlock block;
    block.type = reserved.type;
    block.parent = m_ast.root;
    block.span = spanForLines(reserved.firstLine, reserved.lastLine);
    m_ast.blocks.append(block);
    order.append(static_cast<int>(m_ast.blocks.size()) - 1);
  }
  int cursor = m_reserved.isEmpty() ? 0 : m_reserved.last().lastLine + 1;

  const QVector<int> parsed = m_ast.blocks.at(m_ast.root).children;

  // Line of the next block that md4c did anchor, so a forward absorb never
  // runs into it.
  auto nextAnchoredLine = [&](int from) {
    for(int j = from; j < parsed.size(); ++j) {
      const MdSpan& span = m_ast.blocks.at(parsed.at(j)).span;
      if(span.firstLine >= 0) {
        return span.firstLine;
      }
    }
    return lines;
  };

  // Non-blank lines in [from, to] that no block claimed become Opaque blocks:
  // link reference definitions emit no callbacks at all and would otherwise
  // vanish from the partition.
  auto emitOpaque = [&](int from, int to) {
    int line = from;
    while(line <= to) {
      if(m_src.isBlankLine(line)) {
        ++line;
        continue;
      }
      const int start = line;
      while(line <= to && !m_src.isBlankLine(line)) {
        ++line;
      }
      MdBlock block;
      block.type = BlockType::Opaque;
      block.parent = m_ast.root;
      block.span = spanForLines(start, line - 1);
      m_ast.blocks.append(block);
      order.append(static_cast<int>(m_ast.blocks.size()) - 1);
    }
  };

  for(int i = 0; i < parsed.size();) {
    const int index = parsed.at(i);
    MdSpan span = m_ast.blocks.at(index).span;

    if(span.firstLine < 0) {
      // Nothing anchored this block: a thematic break, an empty fence, an
      // empty list item. Such blocks often come in runs — "***" followed by an
      // empty quote — and a run has to be split rather than handed wholesale
      // to the first of them, or the second would start on a line the first
      // already owns and the partition would overlap.
      //
      // Every markdown block occupies at least one source line, so a group of
      // k blocks always has at least k non-blank lines available: one line
      // each, in order, with the last one taking whatever remains.
      int groupEnd = i;
      while(groupEnd < parsed.size() && m_ast.blocks.at(parsed.at(groupEnd)).span.firstLine < 0) {
        ++groupEnd;
      }
      const int limit = nextAnchoredLine(groupEnd);

      int line = cursor;
      for(int k = i; k < groupEnd; ++k) {
        while(line < limit && m_src.isBlankLine(line)) {
          ++line;
        }
        // Never step back over a line an earlier block already owns, and never
        // past the end of the document: the partition has to stay ordered even
        // when the region turns out to be smaller than expected. The lower
        // bound is itself capped, because the cursor can already sit past the
        // last line once earlier blocks have consumed everything.
        const int lastLine = std::max(lines - 1, 0);
        const int start = std::clamp(line, std::min(cursor, lastLine), lastLine);
        const bool last = (k == groupEnd - 1);
        int stop = start;
        if(last) {
          // The final block of the group closes the region.
          stop = std::max(limit - 1, start);
          line = limit;
        } else if(line < limit) {
          line = start + 1;
        }
        MdSpan groupSpan = spanForLines(start, stop);
        m_ast.blocks[parsed.at(k)].span = groupSpan;
        order.append(parsed.at(k));
        cursor = groupSpan.lastLine + 1;
      }
      i = groupEnd;
      continue;
    }

    // Absorb the non-blank lines that belong to this block but produced no
    // offset of their own: an opening fence, a setext underline, a table's
    // delimiter row, a list marker on its own line.
    //
    // The absorb stops short of any unanchored blocks that follow. They get no
    // offsets at all, so their lines look exactly like lines to absorb — and
    // swallowing one leaves the block that owns it starting on a line this
    // block already claimed. One line is reserved for each of them.
    int reserved = 0;
    for(int k = i + 1; k < parsed.size() && m_ast.blocks.at(parsed.at(k)).span.firstLine < 0; ++k) {
      ++reserved;
    }
    // What has to be reserved is a *non-blank* line each: blank lines are
    // separators, not content, and leaving only those behind would push an
    // unanchored block onto a line this one already took.
    int limit = nextAnchoredLine(i + 1);
    for(int need = reserved; need > 0 && limit - 1 > span.lastLine;) {
      --limit;
      if(!m_src.isBlankLine(limit)) {
        --need;
      }
    }

    while(span.firstLine > cursor && !m_src.isBlankLine(span.firstLine - 1)) {
      --span.firstLine;
    }
    while(span.lastLine + 1 < limit && !m_src.isBlankLine(span.lastLine + 1)) {
      ++span.lastLine;
    }
    if(span.firstLine > cursor) {
      emitOpaque(cursor, span.firstLine - 1);
    }

    span = spanForLines(span.firstLine, span.lastLine);
    m_ast.blocks[index].span = span;
    order.append(index);
    cursor = span.lastLine + 1;
    ++i;
  }

  if(cursor < lines) {
    emitOpaque(cursor, lines - 1);
  }

  // A document of nothing but blank lines produces no blocks at all, and
  // emitOpaque skips blanks on purpose. One block still has to cover it, or
  // the partition stops being total and every caller that maps a line to a
  // block has a hole to handle.
  if(order.isEmpty()) {
    MdBlock block;
    block.type = BlockType::Opaque;
    block.parent = m_ast.root;
    block.span = spanForLines(0, std::max(lines - 1, 0));
    m_ast.blocks.append(block);
    order.append(static_cast<int>(m_ast.blocks.size()) - 1);
  }

  // Close the gaps: each block runs up to the start of the next, so trailing
  // blank lines travel with the block above them and the ranges tile the
  // document with nothing left over.
  for(int i = 0; i < order.size(); ++i) {
    const int index = order.at(i);
    const int stop = (i + 1 < order.size()) ? m_ast.blocks.at(order.at(i + 1)).span.firstLine : lines;
    MdBlock& block = m_ast.blocks[index];
    block.span = spanForLines(block.span.firstLine, std::max(block.span.lastLine, stop - 1));
  }
  if(!order.isEmpty()) {
    MdBlock& first = m_ast.blocks[order.first()];
    first.span = spanForLines(0, first.span.lastLine);
  }

  m_ast.blocks[m_ast.root].children = order;
  m_ast.blocks[m_ast.root].span = spanForLines(0, std::max(lines - 1, 0));
}

MdAst Builder::run() {
  QByteArray buffer(m_src.data(), m_src.byteCount());

  if(m_options.frontmatter) {
    Reserved reserved;
    if(detectFrontmatter(m_src, &reserved)) {
      m_reserved.append(reserved);
      const int from = m_src.lineStartByte(reserved.firstLine);
      const int to = m_src.lineEndByte(reserved.lastLine);
      for(int i = from; i < to; ++i) {
        if(buffer.at(i) != '\n') {
          buffer[i] = ' ';
        }
      }
    }
  }

  // Only now, after every mutation: writing through operator[] can detach the
  // QByteArray and move its data, and the anchors are pointer arithmetic
  // against exactly this address.
  m_base = buffer.constData();
  m_baseSize = static_cast<int>(buffer.size());

  MD_PARSER parser{};
  parser.abi_version = 0;
  parser.flags =
      MD_FLAG_TABLES | MD_FLAG_STRIKETHROUGH | MD_FLAG_TASKLISTS | MD_FLAG_PERMISSIVEAUTOLINKS | MD_FLAG_LATEXMATHSPANS | MD_FLAG_WIKILINKS;
  // md4c calls each of these unconditionally, so all five must be set.
  parser.enter_block = [](MD_BLOCKTYPE type, void* detail, void* userdata) {
    return static_cast<Builder*>(userdata)->onEnterBlock(type, detail);
  };
  parser.leave_block = [](MD_BLOCKTYPE type, void* detail, void* userdata) {
    return static_cast<Builder*>(userdata)->onLeaveBlock(type, detail);
  };
  parser.enter_span = [](MD_SPANTYPE type, void* detail, void* userdata) {
    return static_cast<Builder*>(userdata)->onEnterSpan(type, detail);
  };
  parser.leave_span = [](MD_SPANTYPE type, void*, void* userdata) {
    return static_cast<Builder*>(userdata)->onLeaveSpan(type);
  };
  parser.text = [](MD_TEXTTYPE type, const MD_CHAR* text, MD_SIZE size, void* userdata) {
    return static_cast<Builder*>(userdata)->onText(type, text, size);
  };

  md_parse(buffer.constData(), static_cast<MD_SIZE>(buffer.size()), &parser, this);

  // md4c parses the copy, but every offset was interpreted against the
  // original, which is byte-for-byte identical apart from the blanked regions.
  if(m_ast.root < 0) {
    m_ast.root = addBlock(BlockType::Document);
  }
  assignSpans();
  return m_ast;
}

}  // namespace

MdAst parse(const MdSourceMap& src, const MdParseOptions& options) {
  Builder builder(src, options);
  return builder.run();
}

MdAst parse(const QString& markdown, const MdParseOptions& options) {
  return parse(MdSourceMap(markdown), options);
}

}  // namespace heap::md
