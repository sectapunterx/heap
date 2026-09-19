// Extensions and rich-text rendering.
//
// Two layers are covered. MdExtensions re-labels blocks that are ordinary
// markdown carrying a convention — a quote that opens with "[!NOTE]", a
// paragraph that opens with "[^id]:", a paragraph that is nothing but display
// maths. Re-labelling must never disturb the source ranges, so that is checked
// too. MdHtml turns inline content into the HTML subset Qt Quick renders, and
// is the only place in the engine that emits markup.
//
// Most of the assertions here are about what must *not* come out: document
// text is always escaped, decorations never fire inside code, and no tag is
// emitted that would make Qt fetch something over the network.

#include "MdPartitionCheck.h"

#include "markdown/MdExtensions.h"
#include "markdown/MdHtml.h"
#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"

#include <QString>

#include <gtest/gtest.h>

using namespace heap::md;

namespace {

const MdBlock* firstOfType(const MdAst& ast, BlockType type) {
  for(const MdBlock& block : ast.blocks) {
    if(block.type == type) {
      return &block;
    }
  }
  return nullptr;
}

// A palette with recognisable values, so a test can tell which rule coloured
// a run without depending on the real theme.
MdHtmlOptions testOptions() {
  MdHtmlOptions options;
  options.palette.link = QStringLiteral("#1111ff");
  options.palette.code = QStringLiteral("#222222");
  options.palette.codeBackground = QStringLiteral("#eeeeee");
  options.palette.highlightBackground = QStringLiteral("#ffff00");
  options.palette.mention = QStringLiteral("#00aa00");
  options.palette.ticket = QStringLiteral("#aa0000");
  options.palette.tag = QStringLiteral("#0000aa");
  options.palette.math = QStringLiteral("#aa00aa");
  return options;
}

// Rich text for the first block of `markdown` whose type matches.
QString renderFirst(const QString& markdown, BlockType type, MdHtmlOptions options = testOptions()) {
  const MdAst ast = parse(markdown);
  const MdBlock* block = firstOfType(ast, type);
  if(block == nullptr) {
    return QStringLiteral("<no block of that type>");
  }
  if(options.footnoteNumbers.isEmpty()) {
    options.footnoteNumbers = footnoteNumbers(ast);
  }
  return inlineHtml(ast, *block, options);
}

QString renderParagraph(const QString& markdown) {
  return renderFirst(markdown, BlockType::Paragraph);
}

}  // namespace

// ── Callouts ────────────────────────────────────────────────────────

TEST(MdExtensionsTest, RecognisesCallouts) {
  const MdAst ast = parse(QStringLiteral("> [!WARNING] Mind the gap\n> body text\n"));
  const MdBlock* callout = firstOfType(ast, BlockType::Callout);
  ASSERT_NE(callout, nullptr);
  EXPECT_EQ(callout->calloutKind, QStringLiteral("warning"));
  EXPECT_EQ(callout->calloutTitle, QStringLiteral("Mind the gap"));
  EXPECT_FALSE(callout->foldable);
}

TEST(MdExtensionsTest, CalloutWithoutATitleIsNamedAfterItsKind) {
  const MdAst ast = parse(QStringLiteral("> [!note]\n> just a body\n"));
  const MdBlock* callout = firstOfType(ast, BlockType::Callout);
  ASSERT_NE(callout, nullptr);
  EXPECT_EQ(callout->calloutKind, QStringLiteral("note"));
  EXPECT_EQ(callout->calloutTitle, QStringLiteral("note"));
}

TEST(MdExtensionsTest, CalloutFoldMarkers) {
  const MdAst folded = parse(QStringLiteral("> [!TIP]- Collapsed\n> body\n"));
  const MdBlock* a = firstOfType(folded, BlockType::Callout);
  ASSERT_NE(a, nullptr);
  EXPECT_TRUE(a->foldable);
  EXPECT_TRUE(a->startsFolded);

  const MdAst expanded = parse(QStringLiteral("> [!TIP]+ Open\n> body\n"));
  const MdBlock* b = firstOfType(expanded, BlockType::Callout);
  ASSERT_NE(b, nullptr);
  EXPECT_TRUE(b->foldable);
  EXPECT_FALSE(b->startsFolded);
}

TEST(MdExtensionsTest, CalloutMarkerIsNotRepeatedInTheBody) {
  // The header shows the kind and title; the body must not show them again.
  const MdAst ast = parse(QStringLiteral("> [!NOTE] The title\n> body text\n"));
  const MdBlock* paragraph = firstOfType(ast, BlockType::Paragraph);
  ASSERT_NE(paragraph, nullptr);
  const QString body = inlinePlainText(ast, *paragraph);
  EXPECT_FALSE(body.contains(QStringLiteral("[!NOTE]")));
  EXPECT_FALSE(body.contains(QStringLiteral("The title")));
  EXPECT_TRUE(body.contains(QStringLiteral("body text")));
}

TEST(MdExtensionsTest, OrdinaryQuotesAreLeftAlone) {
  const MdAst ast = parse(QStringLiteral("> just a quotation\n"));
  EXPECT_EQ(firstOfType(ast, BlockType::Callout), nullptr);
  EXPECT_NE(firstOfType(ast, BlockType::Quote), nullptr);
}

// ── Footnotes and maths ─────────────────────────────────────────────

TEST(MdExtensionsTest, RecognisesFootnoteDefinitions) {
  const MdAst ast = parse(QStringLiteral("Text[^why].\n\n[^why]: Because of the thing.\n"));
  const MdBlock* definition = firstOfType(ast, BlockType::FootnoteDef);
  ASSERT_NE(definition, nullptr);
  EXPECT_EQ(definition->footnoteId, QStringLiteral("why"));
  EXPECT_TRUE(inlinePlainText(ast, *definition).contains(QStringLiteral("Because of the thing")));
  EXPECT_FALSE(inlinePlainText(ast, *definition).contains(QStringLiteral("[^why]:")));
}

TEST(MdExtensionsTest, NumbersFootnotesByFirstReference) {
  // Numbering follows the reader, not the order the definitions were written.
  const MdAst ast = parse(QStringLiteral("First[^b] then[^a] again[^b].\n\n[^a]: A\n\n[^b]: B\n"));
  const QHash<QString, int> numbers = footnoteNumbers(ast);
  EXPECT_EQ(numbers.value(QStringLiteral("b")), 1);
  EXPECT_EQ(numbers.value(QStringLiteral("a")), 2);
}

TEST(MdExtensionsTest, PromotesADisplayMathParagraph) {
  const MdAst ast = parse(QStringLiteral("text\n\n$$\nE = mc^2\n$$\n\nmore\n"));
  EXPECT_NE(firstOfType(ast, BlockType::MathBlock), nullptr);
}

TEST(MdExtensionsTest, NamesDiagramLanguages) {
  EXPECT_TRUE(isDiagramLanguage(QStringLiteral("mermaid")));
  EXPECT_TRUE(isDiagramLanguage(QStringLiteral("  Mermaid  ")));
  EXPECT_FALSE(isDiagramLanguage(QStringLiteral("cpp")));
  EXPECT_FALSE(isDiagramLanguage(QString()));
}

TEST(MdExtensionsTest, RelabellingDoesNotDisturbTheSourceRanges) {
  // Extensions only rename blocks. If one ever added or reordered a block, the
  // partition would break and every write-back by range with it.
  const QStringList documents{
      QStringLiteral("> [!NOTE] Title\n> body\n\nafter\n"),
      QStringLiteral("ref[^a]\n\n[^a]: definition\n\nafter\n"),
      QStringLiteral("$$\nx\n$$\n\nafter\n"),
      QStringLiteral("> [!TIP]-\n> folded\n\n> plain quote\n\n[^x]: d\n"),
  };
  for(const QString& document : documents) {
    EXPECT_TRUE(heap::md::test::checkPartition(document).isEmpty()) << document.toStdString();
  }
}

// ── Escaping ────────────────────────────────────────────────────────

TEST(MdHtmlTest, EscapesDocumentText) {
  // A note is not a web page. Anything that looks like markup must read as
  // the characters the author typed.
  // Kept inline: a line *starting* with "<script>" is an HTML block in
  // CommonMark, which is a different path and covered separately below.
  const QString html = renderParagraph(QStringLiteral("text <script>alert(1)</script> & \"quotes\"\n"));
  EXPECT_FALSE(html.contains(QStringLiteral("<script>")));
  EXPECT_TRUE(html.contains(QStringLiteral("&lt;script&gt;")));
  EXPECT_TRUE(html.contains(QStringLiteral("&amp;")));
  EXPECT_TRUE(html.contains(QStringLiteral("&quot;")));
}

TEST(MdHtmlTest, ShowsRawInlineHtmlRatherThanInterpretingIt) {
  const QString html = renderParagraph(QStringLiteral("text <b>not bold</b> more\n"));
  EXPECT_TRUE(html.contains(QStringLiteral("&lt;b&gt;")));
}

TEST(MdHtmlTest, EscapesLinkTargets) {
  const QString html = renderParagraph(QStringLiteral("[label](https://example.com/?a=1&b=2)\n"));
  EXPECT_TRUE(html.contains(QStringLiteral("&amp;b=2")));
  EXPECT_FALSE(html.contains(QStringLiteral("?a=1&b=2")));
}

// ── Emphasis, code, links ───────────────────────────────────────────

TEST(MdHtmlTest, RendersBasicMarkup) {
  const QString html = renderParagraph(QStringLiteral("**bold** _em_ ~~gone~~ `code`\n"));
  EXPECT_TRUE(html.contains(QStringLiteral("<b>bold</b>")));
  EXPECT_TRUE(html.contains(QStringLiteral("<i>em</i>")));
  EXPECT_TRUE(html.contains(QStringLiteral("<s>gone</s>")));
  EXPECT_TRUE(html.contains(QStringLiteral("<code>code</code>")));
}

TEST(MdHtmlTest, RendersLinksAndWikiLinks) {
  const QString link = renderParagraph(QStringLiteral("[text](https://example.com)\n"));
  EXPECT_TRUE(link.contains(QStringLiteral("href=\"https://example.com\"")));
  EXPECT_TRUE(link.contains(QStringLiteral("#1111ff")));

  // A wiki link resolves inside heap, so it gets an internal scheme the UI
  // routes rather than a URL the browser would be handed.
  const QString wiki = renderParagraph(QStringLiteral("see [[Some heading]]\n"));
  EXPECT_TRUE(wiki.contains(QStringLiteral("heap://note/")));
  EXPECT_FALSE(wiki.contains(QStringLiteral("href=\"Some heading\"")));
}

// ── Decorations ─────────────────────────────────────────────────────

TEST(MdHtmlTest, RendersHeapDecorations) {
  const QString html = renderParagraph(QStringLiteral("==note== @alice #HEAP-123 #topic\n"));
  EXPECT_TRUE(html.contains(QStringLiteral("#ffff00")));  // highlight
  EXPECT_TRUE(html.contains(QStringLiteral("heap://person/alice")));
  EXPECT_TRUE(html.contains(QStringLiteral("heap://task/HEAP-123")));
  EXPECT_TRUE(html.contains(QStringLiteral("heap://tag/topic")));
}

TEST(MdHtmlTest, TicketReferenceWinsOverTag) {
  // "#HEAP-1" must not read as the tag "HEAP" followed by "-1".
  const QString html = renderParagraph(QStringLiteral("#HEAP-1\n"));
  EXPECT_TRUE(html.contains(QStringLiteral("heap://task/HEAP-1")));
  EXPECT_FALSE(html.contains(QStringLiteral("heap://tag/")));
}

TEST(MdHtmlTest, DecorationsDoNotFireInsideCode) {
  // In a shell snippet "#tag" is a comment and "@host" is not a person.
  const QString html = renderParagraph(QStringLiteral("`ssh @host  # notatag`\n"));
  EXPECT_FALSE(html.contains(QStringLiteral("heap://person/")));
  EXPECT_FALSE(html.contains(QStringLiteral("heap://tag/")));
}

TEST(MdHtmlTest, DecorationsDoNotFireMidWord) {
  const QString html = renderParagraph(QStringLiteral("email a@b.com and c#d\n"));
  EXPECT_FALSE(html.contains(QStringLiteral("heap://person/")));
  EXPECT_FALSE(html.contains(QStringLiteral("heap://tag/d")));
}

TEST(MdHtmlTest, FootnoteReferencesBecomeNumberedSuperscripts) {
  const QString html = renderParagraph(QStringLiteral("Claim[^src].\n\n[^src]: Source\n"));
  EXPECT_TRUE(html.contains(QStringLiteral("<sup>")));
  EXPECT_TRUE(html.contains(QStringLiteral("heap://fn/src")));
  EXPECT_TRUE(html.contains(QStringLiteral(">1<")));
}

TEST(MdHtmlTest, UndefinedFootnoteShowsItsIdRatherThanAMadeUpNumber) {
  const QString html = renderParagraph(QStringLiteral("Claim[^missing].\n"));
  EXPECT_TRUE(html.contains(QStringLiteral("missing")));
}

// ── Images and egress ───────────────────────────────────────────────

TEST(MdHtmlTest, DoesNotEmitRemoteImagesByDefault) {
  // heap says it makes no network requests of its own. An <img> with an http
  // source would make one, to a host chosen by whoever wrote the note, every
  // time the note is opened.
  const QString html = renderParagraph(QStringLiteral("![alt](https://tracker.example/pixel.png)\n"));
  EXPECT_FALSE(html.contains(QStringLiteral("<img")));
  EXPECT_TRUE(html.contains(QStringLiteral("href=\"https://tracker.example/pixel.png\"")));
  EXPECT_TRUE(html.contains(QStringLiteral("alt")));
}

TEST(MdHtmlTest, EmitsRemoteImagesOnceAllowed) {
  MdHtmlOptions options = testOptions();
  options.allowRemoteImages = true;
  const QString html = renderFirst(QStringLiteral("![alt](https://example.com/x.png)\n"), BlockType::Paragraph, options);
  EXPECT_TRUE(html.contains(QStringLiteral("<img")));
}

TEST(MdHtmlTest, LocalImagesAlwaysRender) {
  // An attachment is a file the author already has; nothing leaves the machine.
  const QString html = renderParagraph(QStringLiteral("![diagram](attachments/abc.png)\n"));
  EXPECT_TRUE(html.contains(QStringLiteral("<img")));
  EXPECT_TRUE(html.contains(QStringLiteral("attachments/abc.png")));
}

// ── Maths and plain text ────────────────────────────────────────────

TEST(MdHtmlTest, ShowsMathSourceInItsOwnColour) {
  // Nothing typesets maths in this build; showing the source beats dropping it
  // or rendering it wrongly.
  const QString html = renderParagraph(QStringLiteral("inline $x^2$ here\n"));
  EXPECT_TRUE(html.contains(QStringLiteral("#aa00aa")));
  EXPECT_TRUE(html.contains(QStringLiteral("x^2")));
}

TEST(MdHtmlTest, PlainTextDropsMarkup) {
  const MdAst ast = parse(QStringLiteral("**bold** and [a link](https://x) and `code`\n"));
  const MdBlock* paragraph = firstOfType(ast, BlockType::Paragraph);
  ASSERT_NE(paragraph, nullptr);
  const QString plain = inlinePlainText(ast, *paragraph);
  EXPECT_EQ(plain, QStringLiteral("bold and a link and code"));
}

TEST(MdHtmlTest, HandlesEmptyAndDegenerateInput) {
  EXPECT_NO_FATAL_FAILURE(renderParagraph(QString()));
  EXPECT_NO_FATAL_FAILURE(renderParagraph(QStringLiteral("==\n")));
  EXPECT_NO_FATAL_FAILURE(renderParagraph(QStringLiteral("@ # [^] ==x\n")));
  EXPECT_NO_FATAL_FAILURE(renderParagraph(QStringLiteral("![](  )\n")));
}
