// Markdown parser: AST shape and, above all, source ranges.
//
// CommonMark conformance is md4c's problem — heap vendors a parser precisely
// so it is not this project's. What is tested here is the layer heap adds: the
// byte/UTF-16/line source map, and the guarantee that every top-level block
// knows which lines of the document it came from.
//
// That guarantee is load-bearing. A checkbox click rewrites one character by
// offset; live preview swaps a block for its source slice; the outline jumps
// the caret to a heading. If a range is off by a line, an edit lands in the
// wrong place and the note is silently corrupted. So the partition property —
// ranges are ordered, contiguous, cover everything, and their slices
// re-concatenate to the original — is asserted over every fixture rather than
// spot-checked.

#include "MdPartitionCheck.h"

#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"

#include <QString>
#include <QStringList>

#include <gtest/gtest.h>

using namespace heap::md;
using heap::md::test::checkPartition;
using heap::md::test::partitionFixtures;

namespace {

// Types of the top-level blocks, for readable shape assertions.
QVector<BlockType> topTypes(const MdAst& ast) {
  QVector<BlockType> types;
  for(const int index : ast.topLevel()) {
    types.append(ast.blocks.at(index).type);
  }
  return types;
}

const MdBlock* firstOfType(const MdAst& ast, BlockType type) {
  for(const MdBlock& block : ast.blocks) {
    if(block.type == type) {
      return &block;
    }
  }
  return nullptr;
}

}  // namespace

// ── Source map ──────────────────────────────────────────────────────

TEST(MdSourceMapTest, CountsLines) {
  EXPECT_EQ(MdSourceMap(QString()).lineCount(), 1);
  EXPECT_EQ(MdSourceMap(QStringLiteral("a")).lineCount(), 1);
  EXPECT_EQ(MdSourceMap(QStringLiteral("a\n")).lineCount(), 1);
  EXPECT_EQ(MdSourceMap(QStringLiteral("a\nb")).lineCount(), 2);
  EXPECT_EQ(MdSourceMap(QStringLiteral("a\nb\n")).lineCount(), 2);
  EXPECT_EQ(MdSourceMap(QStringLiteral("a\n\nb\n")).lineCount(), 3);
}

TEST(MdSourceMapTest, ReadsLineText) {
  const MdSourceMap src(QStringLiteral("first\nsecond\nthird\n"));
  EXPECT_EQ(src.lineText(0), QStringLiteral("first"));
  EXPECT_EQ(src.lineText(1), QStringLiteral("second"));
  EXPECT_EQ(src.lineText(2), QStringLiteral("third"));
  EXPECT_EQ(src.lineText(9), QString());
}

TEST(MdSourceMapTest, TreatsEveryCommonMarkLineEndingAsALineEnding) {
  // CommonMark — and md4c with it — ends a line at "\n", "\r\n" or a lone
  // "\r". A bare carriage return really does start a new line, and a source
  // map that missed that would be one line out of step with the parser, so
  // every block range past it would be wrong.
  EXPECT_EQ(MdSourceMap(QStringLiteral("a\r\nb\r\n")).lineCount(), 2);
  EXPECT_EQ(MdSourceMap(QStringLiteral("a\rb\r")).lineCount(), 2);
  EXPECT_EQ(MdSourceMap(QStringLiteral("a\rb")).lineCount(), 2);
  EXPECT_EQ(MdSourceMap(QStringLiteral("a\r\n\rb")).lineCount(), 3);

  const MdSourceMap crlf(QStringLiteral("a\r\nb\r\n"));
  EXPECT_EQ(crlf.lineText(0), QStringLiteral("a"));
  EXPECT_EQ(crlf.lineText(1), QStringLiteral("b"));

  // The terminator is reported separately rather than folded into the text,
  // so rejoining line ranges reproduces the document instead of normalising
  // it to line feeds.
  EXPECT_EQ(crlf.textForLines(0, 0), QStringLiteral("a"));
  EXPECT_EQ(crlf.lineTerminator(0), QStringLiteral("\r\n"));
  EXPECT_EQ(crlf.lineTerminator(1), QStringLiteral("\r\n"));
  EXPECT_EQ(MdSourceMap(QStringLiteral("a\rb")).lineTerminator(0), QStringLiteral("\r"));
  EXPECT_EQ(MdSourceMap(QStringLiteral("a\rb")).lineTerminator(1), QString());

  // Mixed endings in one document, rebuilt byte for byte.
  const QString mixed = QStringLiteral("one\r\ntwo\rthree\nfour");
  const MdSourceMap src(mixed);
  ASSERT_EQ(src.lineCount(), 4);
  QString rebuilt;
  for(int i = 0; i < src.lineCount(); ++i) {
    rebuilt += src.lineText(i) + src.lineTerminator(i);
  }
  EXPECT_EQ(rebuilt, mixed);
}

TEST(MdSourceMapTest, DetectsBlankLines) {
  const MdSourceMap src(QStringLiteral("a\n\n   \n\t\n b\n"));
  EXPECT_FALSE(src.isBlankLine(0));
  EXPECT_TRUE(src.isBlankLine(1));
  EXPECT_TRUE(src.isBlankLine(2));
  EXPECT_TRUE(src.isBlankLine(3));
  EXPECT_FALSE(src.isBlankLine(4));
}

TEST(MdSourceMapTest, MapsBytesToUtf16AcrossMultiByteCharacters) {
  // "Я" is two UTF-8 bytes and one UTF-16 unit; the emoji is four bytes and a
  // surrogate pair. Getting this wrong puts the caret inside a character.
  const QString text = QStringLiteral("aЯ🙂b");
  const MdSourceMap src(text);
  EXPECT_EQ(src.byteCount(), 1 + 2 + 4 + 1);
  EXPECT_EQ(src.utf16Length(), text.size());

  EXPECT_EQ(src.byteToUtf16(0), 0);  // a
  EXPECT_EQ(src.byteToUtf16(1), 1);  // Я
  EXPECT_EQ(src.byteToUtf16(3), 2);  // 🙂
  EXPECT_EQ(src.byteToUtf16(7), 4);  // b, after the surrogate pair
  EXPECT_EQ(src.byteToUtf16(8), text.size());
}

TEST(MdSourceMapTest, Utf16ToByteRoundTrips) {
  const MdSourceMap src(QStringLiteral("aЯ🙂b\nвторая строка\n"));
  for(int byte = 0; byte <= src.byteCount(); ++byte) {
    const int pos = src.byteToUtf16(byte);
    const int back = src.utf16ToByte(pos);
    // A byte inside a character maps to that character's start, so the
    // round-trip lands on a character boundary at or before where it started.
    EXPECT_LE(back, byte) << "byte " << byte;
    EXPECT_EQ(src.byteToUtf16(back), pos) << "byte " << byte;
  }
}

TEST(MdSourceMapTest, ClampsOutOfRangeInput) {
  const MdSourceMap src(QStringLiteral("abc\n"));
  EXPECT_EQ(src.lineOfByte(-5), 0);
  EXPECT_EQ(src.lineOfByte(9999), 0);
  EXPECT_EQ(src.byteToUtf16(-1), 0);
  EXPECT_EQ(src.byteToUtf16(9999), src.utf16Length());
  EXPECT_EQ(src.textForBytes(2, 1), QString());
  EXPECT_FALSE(src.containsByte(-1));
  EXPECT_FALSE(src.containsByte(src.byteCount()));
}

// ── The partition property ──────────────────────────────────────────

TEST(MdParserTest, TopLevelSpansPartitionTheDocument) {
  for(const QString& fixture : partitionFixtures()) {
    const QString problem = checkPartition(fixture);
    EXPECT_TRUE(problem.isEmpty()) << "fixture:\n" << fixture.toStdString() << "\nproblem: " << problem.toStdString();
  }
}

// ── AST shape ───────────────────────────────────────────────────────

TEST(MdParserTest, ReportsHeadingLevelsAndText) {
  const MdAst ast = parse(QStringLiteral("# One\n\n### Three\n"));
  ASSERT_EQ(topTypes(ast), (QVector<BlockType>{BlockType::Heading, BlockType::Heading}));
  EXPECT_EQ(ast.blocks.at(ast.topLevel().at(0)).headingLevel, 1);
  EXPECT_EQ(ast.blocks.at(ast.topLevel().at(1)).headingLevel, 3);

  const MdBlock& first = ast.blocks.at(ast.topLevel().at(0));
  ASSERT_EQ(first.inlines.size(), 1);
  EXPECT_EQ(ast.inlines.at(first.inlines.at(0)).text, QStringLiteral("One"));
}

TEST(MdParserTest, KeepsFenceLanguageAndBody) {
  const MdAst ast = parse(QStringLiteral("```cpp\nint x = 1;\n```\n"));
  const MdBlock* code = firstOfType(ast, BlockType::CodeBlock);
  ASSERT_NE(code, nullptr);
  EXPECT_TRUE(code->fenced);
  EXPECT_EQ(code->codeLanguage, QStringLiteral("cpp"));
  // The span covers both fence lines even though neither produced an offset.
  EXPECT_EQ(code->span.firstLine, 0);
  EXPECT_EQ(code->span.lastLine, 2);
}

TEST(MdParserTest, IndentedCodeIsNotMarkedFenced) {
  const MdAst ast = parse(QStringLiteral("    indented\n"));
  const MdBlock* code = firstOfType(ast, BlockType::CodeBlock);
  ASSERT_NE(code, nullptr);
  EXPECT_FALSE(code->fenced);
  EXPECT_TRUE(code->codeLanguage.isEmpty());
}

TEST(MdParserTest, RecordsTaskItemsAndTheirMarkOffset) {
  const QString markdown = QStringLiteral("- [ ] todo\n- [x] done\n");
  const MdSourceMap src(markdown);
  const MdAst ast = parse(src);

  QVector<const MdBlock*> items;
  for(const MdBlock& block : ast.blocks) {
    if(block.type == BlockType::ListItem) {
      items.append(&block);
    }
  }
  ASSERT_EQ(items.size(), 2);
  EXPECT_TRUE(items.at(0)->isTask);
  EXPECT_EQ(items.at(0)->taskMark, QChar(u' '));
  EXPECT_TRUE(items.at(1)->isTask);
  EXPECT_EQ(items.at(1)->taskMark, QChar(u'x'));

  // The offset must address exactly the character between the brackets, so a
  // click can flip one character and nothing else.
  EXPECT_EQ(markdown.at(src.byteToUtf16(items.at(0)->taskMarkByte)), QChar(u' '));
  EXPECT_EQ(markdown.at(src.byteToUtf16(items.at(1)->taskMarkByte)), QChar(u'x'));
}

TEST(MdParserTest, TaskMarkOffsetSurvivesMultiByteText) {
  // Byte offsets and UTF-16 positions diverge as soon as the line holds
  // non-ASCII, and a task list can sit below one.
  const QString markdown = QStringLiteral("# Заголовок 🙂\n\n- [x] готово\n");
  const MdSourceMap src(markdown);
  const MdAst ast = parse(src);

  const MdBlock* item = firstOfType(ast, BlockType::ListItem);
  ASSERT_NE(item, nullptr);
  ASSERT_TRUE(item->isTask);
  EXPECT_EQ(markdown.at(src.byteToUtf16(item->taskMarkByte)), QChar(u'x'));
}

TEST(MdParserTest, ParsesTableStructure) {
  const MdAst ast = parse(QStringLiteral("| a | b |\n|:--|--:|\n| 1 | 2 |\n"));
  const MdBlock* table = firstOfType(ast, BlockType::Table);
  ASSERT_NE(table, nullptr);
  EXPECT_EQ(table->columnCount, 2);
  EXPECT_EQ(table->span.firstLine, 0);
  EXPECT_EQ(table->span.lastLine, 2);

  const MdBlock* header = firstOfType(ast, BlockType::TableHeaderCell);
  ASSERT_NE(header, nullptr);
  EXPECT_EQ(header->align, ColumnAlign::Left);
}

TEST(MdParserTest, HoldsFrontmatterOutOfTheMarkdown) {
  const MdAst ast = parse(QStringLiteral("---\ntitle: note\n---\n\n# Body\n"));
  const QVector<BlockType> types = topTypes(ast);
  ASSERT_FALSE(types.isEmpty());
  EXPECT_EQ(types.first(), BlockType::Frontmatter);
  // Without the pre-pass, "title: note" between two --- lines parses as a
  // setext heading rather than as data.
  EXPECT_FALSE(types.contains(BlockType::ThematicBreak));
  EXPECT_TRUE(types.contains(BlockType::Heading));

  const MdBlock& frontmatter = ast.blocks.at(ast.topLevel().first());
  EXPECT_EQ(frontmatter.span.firstLine, 0);
  EXPECT_GE(frontmatter.span.lastLine, 2);
}

TEST(MdParserTest, UnclosedFrontmatterIsOrdinaryMarkdown) {
  const MdAst ast = parse(QStringLiteral("---\nnot really frontmatter\n"));
  EXPECT_FALSE(topTypes(ast).contains(BlockType::Frontmatter));
}

TEST(MdParserTest, KeepsLinkReferenceDefinitionsAsOpaqueBlocks) {
  // These produce no callbacks at all. Dropping them would make the partition
  // lose lines, and an edit written back by range would overwrite them.
  const MdAst ast = parse(QStringLiteral("Text with [ref].\n\n[ref]: https://example.com\n"));
  EXPECT_TRUE(topTypes(ast).contains(BlockType::Opaque));
}

TEST(MdParserTest, ResolvesReferenceLinksWithoutStretchingTheBlock) {
  // The link target lives in the definition further down. Anchoring on it
  // would stretch the paragraph's range over the definition too.
  const QString markdown = QStringLiteral("Go to [here][ref] now.\n\n[ref]: https://example.com\n");
  const MdAst ast = parse(markdown);
  const QVector<int>& top = ast.topLevel();
  ASSERT_FALSE(top.isEmpty());
  const MdBlock& paragraph = ast.blocks.at(top.at(0));
  EXPECT_EQ(paragraph.type, BlockType::Paragraph);
  EXPECT_LE(paragraph.span.lastLine, 1);

  bool found = false;
  for(const MdInline& node : ast.inlines) {
    if(node.type == InlineType::Link) {
      EXPECT_EQ(node.href, QStringLiteral("https://example.com"));
      found = true;
    }
  }
  EXPECT_TRUE(found);
}

TEST(MdParserTest, RecordsWikiLinkTargets) {
  const MdAst ast = parse(QStringLiteral("See [[Some heading]].\n"));
  bool found = false;
  for(const MdInline& node : ast.inlines) {
    if(node.type == InlineType::WikiLink) {
      EXPECT_EQ(node.href, QStringLiteral("Some heading"));
      found = true;
    }
  }
  EXPECT_TRUE(found);
}

TEST(MdParserTest, UnderscoreStaysEmphasis) {
  const MdAst ast = parse(QStringLiteral("_emphasis_ and **strong**\n"));
  QVector<InlineType> kinds;
  for(const MdInline& node : ast.inlines) {
    kinds.append(node.type);
  }
  EXPECT_TRUE(kinds.contains(InlineType::Emphasis));
  EXPECT_TRUE(kinds.contains(InlineType::Strong));
  EXPECT_FALSE(kinds.contains(InlineType::Underline));
}

TEST(MdParserTest, InlineSpansPointAtRealSourceText) {
  const QString markdown = QStringLiteral("a **bold** word\n");
  const MdSourceMap src(markdown);
  const MdAst ast = parse(src);

  bool checked = false;
  for(const MdInline& node : ast.inlines) {
    if(node.type == InlineType::Text && node.text == QStringLiteral("bold")) {
      ASSERT_TRUE(node.span.isValid());
      EXPECT_EQ(src.textForBytes(node.span.byteStart, node.span.byteEnd), QStringLiteral("bold"));
      checked = true;
    }
  }
  EXPECT_TRUE(checked);
}

TEST(MdParserTest, NestsListsInsideQuotes) {
  const MdAst ast = parse(QStringLiteral("> - one\n> - two\n"));
  const MdBlock* quote = firstOfType(ast, BlockType::Quote);
  ASSERT_NE(quote, nullptr);
  ASSERT_EQ(quote->children.size(), 1);
  EXPECT_EQ(ast.blocks.at(quote->children.at(0)).type, BlockType::UnorderedList);
}

// ── Degenerate input ────────────────────────────────────────────────

TEST(MdParserTest, HandlesDegenerateInputWithoutCrashing) {
  const QStringList nasty{
      QString(),
      QString::fromUtf8("a\0b\n", 4),
      QStringLiteral("```"),
      QStringLiteral("|||||"),
      QStringLiteral("> > > > > > > > > >"),
      QStringLiteral("- - - - - - - - - -"),
      QStringLiteral("[[[[[[[[[["),
      QStringLiteral("$$$$$$"),
      QStringLiteral("#######nope"),
      QStringLiteral("---\n"),
      QStringLiteral("\r\r\r"),
      QString(2000, QLatin1Char('*')),
      QString(500, QLatin1Char('>')) + QStringLiteral(" deep\n"),
  };
  for(const QString& markdown : nasty) {
    const MdAst ast = parse(markdown);
    EXPECT_TRUE(ast.isValid()) << markdown.left(40).toStdString();
    const QString problem = checkPartition(markdown);
    EXPECT_TRUE(problem.isEmpty()) << markdown.left(40).toStdString() << " -> " << problem.toStdString();
  }
}
