// The rendered view's model.
//
// Rows are flat: a quote holding a list holding a paragraph is three nested
// blocks in the AST but one drawn row that knows how deep it sits. That is
// what keeps the view virtualised, and it is easy to get subtly wrong — a
// nested list that loses its indent, a task item whose checkbox state does not
// survive, a row that forgets which source lines it came from.
//
// The diff is tested too. Typing one character must not rebuild the document:
// the rows that did not change keep their identity so the view reuses their
// delegates, and only the changed span is reported.

#include "markdown/MdBlockModel.h"
#include "markdown/MdHtml.h"
#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"

#include <QAbstractItemModelTester>
#include <QSignalSpy>
#include <QString>

#include <gtest/gtest.h>

using namespace heap::md;

namespace {

// Builds a model from markdown, the way MdDocument does.
class Doc {
 public:
  explicit Doc(const QString& markdown) {
    set(markdown);
  }

  void set(const QString& markdown) {
    m_src = MdSourceMap(markdown);
    m_ast = parse(m_src);
    MdHtmlOptions options;
    options.footnoteNumbers = footnoteNumbers(m_ast);
    m_model.setDocument(m_src, m_ast, options);
  }

  MdBlockModel& model() {
    return m_model;
  }

  int rows() const {
    return m_model.rowCount();
  }

  QVariant at(int row, int role) const {
    return m_model.data(m_model.index(row), role);
  }

  int type(int row) const {
    return at(row, MdBlockModel::TypeRole).toInt();
  }

  QString plain(int row) const {
    return at(row, MdBlockModel::PlainTextRole).toString();
  }

  QVector<int> types() const {
    QVector<int> out;
    for(int i = 0; i < rows(); ++i) {
      out.append(type(i));
    }
    return out;
  }

 private:
  MdSourceMap m_src;
  MdAst m_ast;
  MdBlockModel m_model;
};

int countOfType(const Doc& doc, MdBlockModel::RowType type) {
  int count = 0;
  for(int i = 0; i < doc.rows(); ++i) {
    if(doc.type(i) == static_cast<int>(type)) {
      ++count;
    }
  }
  return count;
}

}  // namespace

TEST(MdBlockModelTest, SatisfiesTheModelContract) {
  Doc doc(QStringLiteral("# H\n\ntext\n\n- a\n- b\n\n| x |\n|---|\n| 1 |\n"));
  QAbstractItemModelTester tester(&doc.model(), QAbstractItemModelTester::FailureReportingMode::Warning);
  EXPECT_GT(doc.rows(), 0);
}

TEST(MdBlockModelTest, ProducesOneRowPerDrawnThing) {
  Doc doc(QStringLiteral("# Title\n\nA paragraph.\n\n---\n\n```cpp\nint x;\n```\n"));
  EXPECT_EQ(doc.types(),
            (QVector<int>{
                static_cast<int>(MdBlockModel::Heading),
                static_cast<int>(MdBlockModel::Paragraph),
                static_cast<int>(MdBlockModel::Rule),
                static_cast<int>(MdBlockModel::Code),
            }));
  EXPECT_EQ(doc.at(0, MdBlockModel::LevelRole).toInt(), 1);
  EXPECT_EQ(doc.at(3, MdBlockModel::LanguageRole).toString(), QStringLiteral("cpp"));
  EXPECT_EQ(doc.at(3, MdBlockModel::CodeRole).toString(), QStringLiteral("int x;"));
}

// ── Lists ───────────────────────────────────────────────────────────

TEST(MdBlockModelTest, DrawsEveryListItem) {
  Doc doc(QStringLiteral("- one\n- two\n- three\n"));
  ASSERT_EQ(doc.rows(), 3);
  EXPECT_EQ(doc.plain(0), QStringLiteral("one"));
  EXPECT_EQ(doc.plain(2), QStringLiteral("three"));
  for(int i = 0; i < 3; ++i) {
    EXPECT_EQ(doc.at(i, MdBlockModel::IndentRole).toInt(), 1) << "row " << i;
    EXPECT_FALSE(doc.at(i, MdBlockModel::MarkerRole).toString().isEmpty()) << "row " << i;
  }
}

TEST(MdBlockModelTest, NumbersOrderedListsFromTheirStart) {
  Doc doc(QStringLiteral("3. third\n4. fourth\n"));
  ASSERT_EQ(doc.rows(), 2);
  EXPECT_EQ(doc.at(0, MdBlockModel::MarkerRole).toString(), QStringLiteral("3."));
  EXPECT_EQ(doc.at(1, MdBlockModel::MarkerRole).toString(), QStringLiteral("4."));
}

TEST(MdBlockModelTest, IndentsNestedLists) {
  Doc doc(QStringLiteral("- outer\n  - inner\n    - deepest\n"));
  ASSERT_EQ(doc.rows(), 3);
  EXPECT_EQ(doc.at(0, MdBlockModel::IndentRole).toInt(), 1);
  EXPECT_EQ(doc.at(1, MdBlockModel::IndentRole).toInt(), 2);
  EXPECT_EQ(doc.at(2, MdBlockModel::IndentRole).toInt(), 3);
  // The bullet glyph changes with depth, so nesting still reads when a line
  // wraps past its indent.
  EXPECT_NE(doc.at(0, MdBlockModel::MarkerRole).toString(), doc.at(1, MdBlockModel::MarkerRole).toString());
}

TEST(MdBlockModelTest, CarriesTaskStateAndItsSourceLine) {
  Doc doc(QStringLiteral("- [ ] open\n- [x] done\n- plain\n"));
  ASSERT_EQ(doc.rows(), 3);
  EXPECT_EQ(doc.at(0, MdBlockModel::TaskStateRole).toInt(), 0);
  EXPECT_EQ(doc.at(1, MdBlockModel::TaskStateRole).toInt(), 1);
  EXPECT_EQ(doc.at(2, MdBlockModel::TaskStateRole).toInt(), -1);
  // The line is what a checkbox click will rewrite.
  EXPECT_EQ(doc.at(0, MdBlockModel::TaskLineRole).toInt(), 0);
  EXPECT_EQ(doc.at(1, MdBlockModel::TaskLineRole).toInt(), 1);
}

TEST(MdBlockModelTest, OnlyTheFirstBlockOfAnItemGetsTheMarker) {
  // A second paragraph in the same item lines up under the first rather than
  // sprouting a second bullet.
  Doc doc(QStringLiteral("- first paragraph\n\n  second paragraph\n\n- next item\n"));
  ASSERT_GE(doc.rows(), 3);
  EXPECT_FALSE(doc.at(0, MdBlockModel::MarkerRole).toString().isEmpty());
  EXPECT_TRUE(doc.at(1, MdBlockModel::MarkerRole).toString().isEmpty());
  EXPECT_FALSE(doc.at(2, MdBlockModel::MarkerRole).toString().isEmpty());
}

// ── Quotes and callouts ─────────────────────────────────────────────

TEST(MdBlockModelTest, CountsQuoteDepth) {
  Doc doc(QStringLiteral("> one\n\n> > two\n"));
  ASSERT_EQ(doc.rows(), 2);
  EXPECT_EQ(doc.at(0, MdBlockModel::QuoteDepthRole).toInt(), 1);
  EXPECT_EQ(doc.at(1, MdBlockModel::QuoteDepthRole).toInt(), 2);
}

TEST(MdBlockModelTest, GivesACalloutAHeaderRowAndABody) {
  Doc doc(QStringLiteral("> [!WARNING] Mind the gap\n> the body text\n"));
  ASSERT_EQ(doc.rows(), 2);
  EXPECT_EQ(doc.type(0), static_cast<int>(MdBlockModel::CalloutHeader));
  EXPECT_EQ(doc.at(0, MdBlockModel::CalloutKindRole).toString(), QStringLiteral("warning"));
  EXPECT_EQ(doc.at(0, MdBlockModel::CalloutTitleRole).toString(), QStringLiteral("Mind the gap"));
  // The body must not repeat the header, and must not lose a character of its
  // own either — an off-by-one here shows up as a stray letter.
  EXPECT_EQ(doc.plain(1), QStringLiteral("the body text"));
}

TEST(MdBlockModelTest, CalloutWithoutATitleKeepsItsWholeBody) {
  Doc doc(QStringLiteral("> [!TIP]\n> run it with --data-dir\n"));
  ASSERT_EQ(doc.rows(), 2);
  EXPECT_EQ(doc.plain(1), QStringLiteral("run it with --data-dir"));
}

// ── Tables, images, footnotes ───────────────────────────────────────

TEST(MdBlockModelTest, FlattensATableRowMajor) {
  Doc doc(QStringLiteral("| a | b |\n|:--|--:|\n| 1 | 2 |\n| 3 | 4 |\n"));
  ASSERT_EQ(doc.rows(), 1);
  EXPECT_EQ(doc.type(0), static_cast<int>(MdBlockModel::Table));
  EXPECT_EQ(doc.at(0, MdBlockModel::TableColumnsRole).toInt(), 2);
  EXPECT_EQ(doc.at(0, MdBlockModel::TableHeaderRole).toInt(), 2);

  const QStringList cells = doc.at(0, MdBlockModel::TableCellsRole).toStringList();
  ASSERT_EQ(cells.size(), 6);
  EXPECT_EQ(cells.at(0), QStringLiteral("a"));
  EXPECT_EQ(cells.at(2), QStringLiteral("1"));
  EXPECT_EQ(cells.at(5), QStringLiteral("4"));

  const QVariantList align = doc.at(0, MdBlockModel::TableAlignRole).toList();
  ASSERT_EQ(align.size(), 2);
  EXPECT_EQ(align.at(0).toInt(), static_cast<int>(ColumnAlign::Left));
  EXPECT_EQ(align.at(1).toInt(), static_cast<int>(ColumnAlign::Right));
}

TEST(MdBlockModelTest, PromotesAParagraphThatIsOnlyAnImage) {
  Doc doc(QStringLiteral("![alt text](attachments/x.png)\n\ntext with ![inline](y.png) in it\n"));
  ASSERT_EQ(doc.rows(), 2);
  EXPECT_EQ(doc.type(0), static_cast<int>(MdBlockModel::Image));
  EXPECT_EQ(doc.at(0, MdBlockModel::ImageSourceRole).toString(), QStringLiteral("attachments/x.png"));
  EXPECT_FALSE(doc.at(0, MdBlockModel::ImageIsRemoteRole).toBool());
  // An image among words stays part of the paragraph.
  EXPECT_EQ(doc.type(1), static_cast<int>(MdBlockModel::Paragraph));
}

TEST(MdBlockModelTest, MarksRemoteImages) {
  Doc doc(QStringLiteral("![x](https://example.com/a.png)\n"));
  ASSERT_EQ(doc.rows(), 1);
  EXPECT_TRUE(doc.at(0, MdBlockModel::ImageIsRemoteRole).toBool());
}

TEST(MdBlockModelTest, CollectsFootnotesIntoASectionAtTheEnd) {
  Doc doc(QStringLiteral("A claim[^a] and another[^b].\n\n[^a]: first\n\nmiddle paragraph\n\n[^b]: second\n"));
  // Definitions are gathered below, in the order a reader meets the
  // references, wherever they were written.
  EXPECT_EQ(countOfType(doc, MdBlockModel::FootnoteHeading), 1);
  EXPECT_EQ(countOfType(doc, MdBlockModel::FootnoteDef), 2);
  EXPECT_EQ(doc.type(doc.rows() - 3), static_cast<int>(MdBlockModel::FootnoteHeading));
  EXPECT_EQ(doc.at(doc.rows() - 2, MdBlockModel::FootnoteNumberRole).toInt(), 1);
  EXPECT_EQ(doc.at(doc.rows() - 1, MdBlockModel::FootnoteNumberRole).toInt(), 2);
}

TEST(MdBlockModelTest, MarksDiagramLanguages) {
  Doc doc(QStringLiteral("```mermaid\ngraph TD; A-->B;\n```\n"));
  ASSERT_EQ(doc.rows(), 1);
  EXPECT_TRUE(doc.at(0, MdBlockModel::IsDiagramRole).toBool());
}

// ── Source mapping ──────────────────────────────────────────────────

TEST(MdBlockModelTest, MapsRowsBackToSourceLines) {
  Doc doc(QStringLiteral("# One\n\npara\n\n- item\n"));
  ASSERT_EQ(doc.rows(), 3);
  EXPECT_EQ(doc.model().firstLineOfRow(0), 0);
  EXPECT_EQ(doc.model().firstLineOfRow(1), 2);
  EXPECT_EQ(doc.model().firstLineOfRow(2), 4);

  EXPECT_EQ(doc.model().rowForLine(0), 0);
  EXPECT_EQ(doc.model().rowForLine(2), 1);
  EXPECT_EQ(doc.model().rowForLine(4), 2);
  // A blank line belongs to the row above it, so scroll sync never lands in
  // a gap between rows.
  EXPECT_EQ(doc.model().rowForLine(3), 1);
}

// ── The diff ────────────────────────────────────────────────────────

TEST(MdBlockModelTest, EditingOneParagraphTouchesOnlyThatRow) {
  Doc doc(QStringLiteral("# Title\n\nfirst\n\nsecond\n\nthird\n"));
  ASSERT_EQ(doc.rows(), 4);

  const auto idOf = [&](int row) {
    return doc.at(row, MdBlockModel::BlockIdRole).toULongLong();
  };
  const auto before = QVector<quint64>{idOf(0), idOf(1), idOf(2), idOf(3)};

  QSignalSpy changed(&doc.model(), &QAbstractItemModel::dataChanged);
  QSignalSpy inserted(&doc.model(), &QAbstractItemModel::rowsInserted);
  QSignalSpy removed(&doc.model(), &QAbstractItemModel::rowsRemoved);

  doc.set(QStringLiteral("# Title\n\nfirst\n\nsecond!\n\nthird\n"));

  EXPECT_EQ(inserted.count(), 0);
  EXPECT_EQ(removed.count(), 0);
  ASSERT_EQ(changed.count(), 1);
  EXPECT_EQ(changed.at(0).at(0).toModelIndex().row(), 2);
  EXPECT_EQ(changed.at(0).at(1).toModelIndex().row(), 2);

  // Untouched rows keep their identity, so their delegates are reused rather
  // than rebuilt — that is the difference between typing smoothly and not.
  EXPECT_EQ(idOf(0), before.at(0));
  EXPECT_EQ(idOf(1), before.at(1));
  EXPECT_EQ(idOf(3), before.at(3));
  EXPECT_NE(idOf(2), before.at(2));
}

TEST(MdBlockModelTest, AddingAParagraphInsertsOneRow) {
  Doc doc(QStringLiteral("one\n\ntwo\n"));
  ASSERT_EQ(doc.rows(), 2);

  QSignalSpy inserted(&doc.model(), &QAbstractItemModel::rowsInserted);
  doc.set(QStringLiteral("one\n\nmiddle\n\ntwo\n"));

  EXPECT_EQ(doc.rows(), 3);
  ASSERT_EQ(inserted.count(), 1);
  EXPECT_EQ(inserted.at(0).at(1).toInt(), 1);
  EXPECT_EQ(inserted.at(0).at(2).toInt(), 1);
  EXPECT_EQ(doc.plain(1), QStringLiteral("middle"));
}

TEST(MdBlockModelTest, RemovingAParagraphRemovesOneRow) {
  Doc doc(QStringLiteral("one\n\nmiddle\n\ntwo\n"));
  ASSERT_EQ(doc.rows(), 3);

  QSignalSpy removed(&doc.model(), &QAbstractItemModel::rowsRemoved);
  doc.set(QStringLiteral("one\n\ntwo\n"));

  EXPECT_EQ(doc.rows(), 2);
  ASSERT_EQ(removed.count(), 1);
  EXPECT_EQ(doc.plain(1), QStringLiteral("two"));
}

TEST(MdBlockModelTest, HandlesEmptyAndDegenerateInput) {
  Doc empty{QString()};
  EXPECT_GE(empty.rows(), 0);

  Doc nasty(QStringLiteral("> > >\n\n|||\n\n```\n\n- \n"));
  EXPECT_NO_FATAL_FAILURE(nasty.types());

  // Going from content to nothing and back must not leave stale rows.
  Doc doc(QStringLiteral("text\n"));
  doc.set(QString());
  EXPECT_LE(doc.rows(), 1);
  doc.set(QStringLiteral("# back\n"));
  ASSERT_EQ(doc.rows(), 1);
  EXPECT_EQ(doc.type(0), static_cast<int>(MdBlockModel::Heading));
}
