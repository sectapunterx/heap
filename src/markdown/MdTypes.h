#pragma once

#include <QChar>
#include <QString>
#include <QVector>

namespace heap::md {

// The parsed shape of a markdown document.
//
// Blocks and inlines are stored as flat vectors with parent/child indices
// rather than as an owning tree. The rendered view is a flat list of rows, the
// diff that keeps it in sync compares slices, and the editor asks questions
// like "which block holds this line" — all of which are cheap over a vector
// and awkward over a pointer graph. Indices stay valid for the lifetime of one
// MdDocument; they are never persisted.

enum class BlockType : quint8 {
  Document,
  Quote,
  UnorderedList,
  OrderedList,
  ListItem,
  ThematicBreak,
  Heading,
  CodeBlock,  // fenced or indented; `fenced` says which
  HtmlBlock,
  Paragraph,
  Table,
  TableHead,
  TableBody,
  TableRow,
  TableHeaderCell,
  TableCell,
  // Produced by heap rather than md4c:
  Frontmatter,  // a leading --- … --- block, held out of the parse
  Callout,      // a quote opening with "[!NOTE]" and friends
  MathBlock,    // a paragraph that is nothing but $$ … $$
  FootnoteDef,  // a paragraph opening with "[^id]:"
  Opaque,       // source that produced no block of its own, e.g. a link
                // reference definition. Carried so the partition stays total.
};

enum class InlineType : quint8 {
  Text,
  Emphasis,
  Strong,
  Strikethrough,
  Underline,
  Code,
  Link,
  Image,
  WikiLink,
  // Produced by heap's inline decorations rather than by md4c:
  Highlight,    // ==text==
  Mention,      // @someone
  TicketRef,    // #HEAP-123
  Tag,          // #topic
  FootnoteRef,  // [^id]
  LatexMath,
  LatexMathDisplay,
  HtmlInline,
  SoftBreak,
  HardBreak,
};

enum class ColumnAlign : quint8 { Default, Left, Center, Right };

// Half-open byte range in the source, plus the closed line range covering it.
// Lines are what the UI works in; bytes are what md4c reports.
struct MdSpan {
  int byteStart = -1;
  int byteEnd = -1;
  int firstLine = -1;
  int lastLine = -1;

  bool isValid() const {
    return firstLine >= 0 && lastLine >= firstLine;
  }

  int lineCount() const {
    return isValid() ? (lastLine - firstLine + 1) : 0;
  }
};

struct MdInline {
  InlineType type = InlineType::Text;
  int parent = -1;
  QVector<int> children;

  // Leaf content, already decoded: entities resolved, NULs replaced.
  QString text;

  // Link, Image and WikiLink.
  QString href;
  QString title;

  // Where the *content* of this node came from, when it is a slice of the
  // source. Synthesized text (an entity, a normalised line break) leaves this
  // invalid — see MdSourceMap::containsByte for why that distinction matters.
  MdSpan span;
};

struct MdBlock {
  BlockType type = BlockType::Paragraph;
  int parent = -1;
  QVector<int> children;

  // Inline content of a leaf block: indices into MdAst::inlines. Empty for
  // container blocks.
  QVector<int> inlines;

  // ── Per-type detail ─────────────────────────────────────────────
  int headingLevel = 0;                      // Heading: 1..6
  bool fenced = false;                       // CodeBlock: fenced vs indented
  QString codeLanguage;                      // CodeBlock: the fence info string
  bool tight = false;                        // UnorderedList / OrderedList
  int listStart = 1;                         // OrderedList
  QChar listMark;                            // list marker or ordered delimiter
  bool isTask = false;                       // ListItem
  QChar taskMark;                            // ListItem: the character between [ and ]
  int taskMarkByte = -1;                     // ListItem: its byte offset in the source
  ColumnAlign align = ColumnAlign::Default;  // table cells
  int columnCount = 0;                       // Table

  // Callout: the kind as written, lower-cased ("note", "warning", "tip", …),
  // the title for its header, and whether the source asked for it to start
  // folded ("[!NOTE]-") or expanded ("[!NOTE]+").
  QString calloutKind;
  QString calloutTitle;
  bool foldable = false;
  bool startsFolded = false;

  QString footnoteId;  // FootnoteDef: the id between "[^" and "]:"

  // Source range. Every block gets one, and the ranges of the document's
  // top-level blocks tile it completely — see MdParser for the guarantee.
  MdSpan span;
};

struct MdAst {
  QVector<MdBlock> blocks;
  QVector<MdInline> inlines;

  // Index of the Document block. -1 only if parsing failed outright.
  int root = -1;

  bool isValid() const {
    return root >= 0 && root < blocks.size();
  }

  // Top-level blocks, in document order: the children of the root.
  const QVector<int>& topLevel() const {
    static const QVector<int> kNone;
    return isValid() ? blocks.at(root).children : kNone;
  }
};

}  // namespace heap::md
