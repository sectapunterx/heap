// Outline, sections and the wiki-link graph.
//
// These answers used to come from two regular expressions applied line by
// line, which cannot see what the document actually is. A line of shell inside
// a fenced code block looked like a heading, so `# install deps` appeared in
// the outline and silently answered a [[install deps]] link. A setext heading
// was never a heading at all, because it is spread over two lines. Reading the
// AST instead makes both fall out of data the parse already produced.
//
// The cases below are mostly those two bugs, plus the section boundaries a
// fold or a per-heading search result depends on.

#include "markdown/MdOutline.h"
#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"
#include "notes/NoteLinks.h"

#include <QString>
#include <QVariantMap>

#include <gtest/gtest.h>

using namespace heap::md;

namespace {

QVector<MdHeading> outlineOf(const QString& markdown) {
  const MdSourceMap src(markdown);
  return outline(src, parse(src));
}

QVector<MdWikiRef> refsOf(const QString& markdown) {
  const MdSourceMap src(markdown);
  return wikiRefs(src, parse(src));
}

QStringList headingTexts(const QString& markdown) {
  QStringList out;
  for(const MdHeading& heading : outlineOf(markdown)) {
    out << heading.text;
  }
  return out;
}

}  // namespace

TEST(MdOutlineTest, ReadsHeadingsInDocumentOrder) {
  const QVector<MdHeading> headings = outlineOf(QStringLiteral("# One\n\ntext\n\n## Two\n\n### Three\n"));
  ASSERT_EQ(headings.size(), 3);
  EXPECT_EQ(headings.at(0).text, QStringLiteral("One"));
  EXPECT_EQ(headings.at(0).level, 1);
  EXPECT_EQ(headings.at(0).line, 0);
  EXPECT_EQ(headings.at(1).text, QStringLiteral("Two"));
  EXPECT_EQ(headings.at(1).level, 2);
  EXPECT_EQ(headings.at(1).line, 4);
  EXPECT_EQ(headings.at(2).level, 3);
}

TEST(MdOutlineTest, IgnoresHashesInsideFencedCode) {
  // The bug this replaces: a comment in a shell snippet was indexed as a
  // heading and answered wiki links.
  const QString markdown = QStringLiteral(
      "# Real heading\n"
      "\n"
      "```bash\n"
      "# install deps\n"
      "## not a heading either\n"
      "```\n");
  EXPECT_EQ(headingTexts(markdown), QStringList{QStringLiteral("Real heading")});
}

TEST(MdOutlineTest, IgnoresHashesInsideIndentedCode) {
  const QString markdown = QStringLiteral("text\n\n    # indented, not a heading\n\n# Actual\n");
  EXPECT_EQ(headingTexts(markdown), QStringList{QStringLiteral("Actual")});
}

TEST(MdOutlineTest, FindsSetextHeadings) {
  // Spread over two lines, so a per-line regex could never see it.
  const QVector<MdHeading> headings = outlineOf(QStringLiteral("Title\n=====\n\nSub\n---\n\nbody\n"));
  ASSERT_EQ(headings.size(), 2);
  EXPECT_EQ(headings.at(0).text, QStringLiteral("Title"));
  EXPECT_EQ(headings.at(0).level, 1);
  EXPECT_EQ(headings.at(1).text, QStringLiteral("Sub"));
  EXPECT_EQ(headings.at(1).level, 2);
}

TEST(MdOutlineTest, StripsInlineMarkupFromHeadingText) {
  // A [[link]] spells the heading the way it reads, not the way it is written.
  EXPECT_EQ(headingTexts(QStringLiteral("## **Bold** and `code` title\n")), QStringList{QStringLiteral("Bold and code title")});
}

TEST(MdOutlineTest, FindsHeadingsInsideContainers) {
  const QString markdown = QStringLiteral("> # Quoted heading\n\n- ## Heading in a list item\n");
  const QStringList texts = headingTexts(markdown);
  EXPECT_TRUE(texts.contains(QStringLiteral("Quoted heading")));
  EXPECT_TRUE(texts.contains(QStringLiteral("Heading in a list item")));
}

TEST(MdOutlineTest, SectionRunsToTheNextHeadingOfSameOrHigherRank) {
  const QString markdown = QStringLiteral(
      "# One\n"        // 0
      "body of one\n"  // 1
      "\n"             // 2
      "## Two\n"       // 3
      "body of two\n"  // 4
      "\n"             // 5
      "### Three\n"    // 6
      "deep body\n"    // 7
      "\n"             // 8
      "## Four\n"      // 9
      "last body\n");  // 10
  const QVector<MdHeading> headings = outlineOf(markdown);
  ASSERT_EQ(headings.size(), 4);

  // "# One" owns everything, because nothing below it is a level 1.
  EXPECT_EQ(headings.at(0).sectionFirstLine, 0);
  EXPECT_EQ(headings.at(0).sectionLastLine, 10);
  // "## Two" stops at "## Four", not at the "### Three" nested inside it.
  EXPECT_EQ(headings.at(1).sectionFirstLine, 3);
  EXPECT_EQ(headings.at(1).sectionLastLine, 8);
  EXPECT_EQ(headings.at(2).sectionFirstLine, 6);
  EXPECT_EQ(headings.at(2).sectionLastLine, 8);
  EXPECT_EQ(headings.at(3).sectionLastLine, 10);
}

TEST(MdOutlineTest, HeadingOffsetPointsAtTheHeadingLine) {
  const QString markdown = QStringLiteral("intro\n\n## Target heading\n\nbody\n");
  const QVector<MdHeading> headings = outlineOf(markdown);
  ASSERT_EQ(headings.size(), 1);
  EXPECT_EQ(markdown.mid(headings.at(0).utf16Offset, 16), QStringLiteral("## Target headin"));
}

TEST(MdOutlineTest, HeadingOffsetSurvivesMultiByteTextAbove) {
  // The offset is a UTF-16 position, so a Cyrillic or emoji line above must
  // not shift it — this is what a jump-to-heading would get wrong.
  const QString markdown = QStringLiteral("Привет 🙂 мир\n\n## Цель\n");
  const QVector<MdHeading> headings = outlineOf(markdown);
  ASSERT_EQ(headings.size(), 1);
  EXPECT_EQ(markdown.mid(headings.at(0).utf16Offset, 7), QStringLiteral("## Цель"));
}

// ── Wiki links ──────────────────────────────────────────────────────

TEST(MdOutlineTest, CollectsWikiRefsWithLines) {
  const QString markdown = QStringLiteral("# A\n\nsee [[Target]] here\n\nand [[Other]]\n");
  const QVector<MdWikiRef> refs = refsOf(markdown);
  ASSERT_EQ(refs.size(), 2);
  EXPECT_EQ(refs.at(0).target, QStringLiteral("Target"));
  EXPECT_EQ(refs.at(0).line, 2);
  EXPECT_EQ(refs.at(0).lineText, QStringLiteral("see [[Target]] here"));
  EXPECT_EQ(refs.at(1).target, QStringLiteral("Other"));
  EXPECT_EQ(refs.at(1).line, 4);
}

TEST(MdOutlineTest, IgnoresWikiLinksInCode) {
  // Text that looks like a link inside a snippet is not one.
  const QString markdown = QStringLiteral("```\n[[not a link]]\n```\n\nalso `[[not one]]`\n\nbut [[this is]]\n");
  const QVector<MdWikiRef> refs = refsOf(markdown);
  ASSERT_EQ(refs.size(), 1);
  EXPECT_EQ(refs.at(0).target, QStringLiteral("this is"));
}

TEST(MdOutlineTest, WikiRefOffsetPointsInsideTheBrackets) {
  const QString markdown = QStringLiteral("text [[Target]] more\n");
  const QVector<MdWikiRef> refs = refsOf(markdown);
  ASSERT_EQ(refs.size(), 1);
  EXPECT_EQ(markdown.mid(refs.at(0).utf16Offset, 6), QStringLiteral("Target"));
}

// ── The NoteLinks facade QML calls ──────────────────────────────────

TEST(MdOutlineTest, NoteLinksNoLongerSeesHeadingsInCode) {
  const QString markdown = QStringLiteral("# Setup\n\n```sh\n# clone the repo\n```\n");
  EXPECT_EQ(heap::notes::collectHeadings(markdown), QStringList{QStringLiteral("Setup")});
  // And the phantom heading no longer resolves a link to it.
  const QVariantList backlinks = heap::notes::collectBacklinks(markdown + QStringLiteral("\nsee [[clone the repo]]\n"));
  ASSERT_EQ(backlinks.size(), 1);
  EXPECT_FALSE(backlinks.at(0).toMap().value(QStringLiteral("resolved")).toBool());
}

TEST(MdOutlineTest, NoteLinksResolvesRegardlessOfCase) {
  // headingOffset() has always matched case-insensitively; collectBacklinks()
  // used to require an exact match, so a link could jump to a heading it
  // claimed was missing. They agree now.
  const QString markdown = QStringLiteral("# Setup\n\nsee [[setup]]\n");
  const QVariantList backlinks = heap::notes::collectBacklinks(markdown);
  ASSERT_EQ(backlinks.size(), 1);
  EXPECT_TRUE(backlinks.at(0).toMap().value(QStringLiteral("resolved")).toBool());
  EXPECT_GE(heap::notes::headingOffset(markdown, QStringLiteral("setup")), 0);
}

TEST(MdOutlineTest, NoteLinksHandlesEmptyAndDegenerateInput) {
  EXPECT_TRUE(heap::notes::collectHeadings(QString()).isEmpty());
  EXPECT_TRUE(heap::notes::collectBacklinks(QString()).isEmpty());
  EXPECT_EQ(heap::notes::headingOffset(QString(), QStringLiteral("x")), -1);
  EXPECT_EQ(heap::notes::headingOffset(QStringLiteral("# A\n"), QString()), -1);
  EXPECT_TRUE(heap::notes::collectHeadings(QStringLiteral("#####\n\n```\n")).isEmpty());
}
