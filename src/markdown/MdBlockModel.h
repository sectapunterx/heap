#pragma once

#include "markdown/MdHtml.h"
#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"

#include <QAbstractListModel>
#include <QStringList>
#include <QVariantList>

namespace heap::md {

// The rendered view's model: one row per thing that gets drawn.
//
// Rows are flat, not a tree. A quote holding a list holding a paragraph is
// three nested blocks in the AST but one drawn row, carrying the depth and
// indent it needs to look nested. Flat rows are what lets the view stay
// virtualised — a note with two thousand task items draws the dozen on screen
// — and what lets a keystroke re-lay-out one paragraph rather than the whole
// document.
//
// Every row remembers which top-level block it came from, so a row can be
// mapped back to the source lines that produced it and an edit can be written
// to exactly the right place.
class MdBlockModel : public QAbstractListModel {
  Q_OBJECT

 public:
  enum RowType {
    Paragraph,
    Heading,
    Code,
    Table,
    Rule,
    Image,
    Math,
    Html,
    Frontmatter,
    CalloutHeader,
    FootnoteHeading,  // the "Footnotes" separator above the definitions
    FootnoteDef,
    Blank,  // a gap the source has but nothing draws; keeps the model total
  };
  Q_ENUM(RowType)

  enum Role {
    TypeRole = Qt::UserRole + 1,
    HtmlRole,        // rich text for text-bearing rows
    PlainTextRole,   // same content without markup, for accessibility
    LevelRole,       // Heading: 1..6
    LanguageRole,    // Code: the fence info string
    CodeRole,        // Code: the body, verbatim
    IsDiagramRole,   // Code: a language nothing here can draw, e.g. mermaid
    QuoteDepthRole,  // how many block quotes enclose this row
    IndentRole,      // list nesting, 0 for top level
    MarkerRole,      // "•", "3." or empty
    TaskStateRole,   // -1 not a task, 0 open, 1 done
    TaskLineRole,    // source line of the task item, for the checkbox click
    CalloutKindRole,
    CalloutTitleRole,
    FoldableRole,
    StartsFoldedRole,
    ImageSourceRole,
    ImageAltRole,
    ImageIsRemoteRole,
    TableAlignRole,  // QVariantList of ColumnAlign, one per column
    TableCellsRole,  // flat QStringList of cell rich text, row-major
    TableColumnsRole,
    TableHeaderRole,  // number of leading cells that are header cells
    FootnoteIdRole,
    FootnoteNumberRole,
    LooseRole,      // list item that wants paragraph spacing
    FirstLineRole,  // source range of the row's own content
    LastLineRole,
    BlockIndexRole,  // index of the top-level block this row belongs to
    BlockIdRole,     // stable while the block's content is unchanged
  };

  explicit MdBlockModel(QObject* parent = nullptr);

  int rowCount(const QModelIndex& parent = {}) const override;
  QVariant data(const QModelIndex& index, int role) const override;
  QHash<int, QByteArray> roleNames() const override;

  // Rebuild from a parsed document. Rows that did not change keep their
  // identity, so the view reuses their delegates instead of rebuilding every
  // one on each keystroke.
  void setDocument(const MdSourceMap& src, const MdAst& ast, const MdHtmlOptions& options);

  // ── Mapping between rows and source ─────────────────────────────
  Q_INVOKABLE int rowForLine(int line) const;
  Q_INVOKABLE int firstLineOfRow(int row) const;
  Q_INVOKABLE int lastLineOfRow(int row) const;

 private:
  struct Row {
    RowType type = Paragraph;
    QString html;
    QString plainText;
    int level = 0;
    QString language;
    QString code;
    bool isDiagram = false;
    int quoteDepth = 0;
    int indent = 0;
    QString marker;
    int taskState = -1;
    int taskLine = -1;
    QString calloutKind;
    QString calloutTitle;
    bool foldable = false;
    bool startsFolded = false;
    QString imageSource;
    QString imageAlt;
    bool imageIsRemote = false;
    QVariantList tableAlign;
    QStringList tableCells;
    int tableColumns = 0;
    int tableHeaderCells = 0;
    QString footnoteId;
    int footnoteNumber = 0;
    bool loose = false;
    int firstLine = 0;
    int lastLine = 0;
    int blockIndex = -1;
    quint64 id = 0;

    // Everything a delegate draws. Two rows that agree on this can be swapped
    // without the view noticing, which is what the diff relies on.
    bool sameContent(const Row& other) const;
  };

  QVector<Row> m_rows;
  quint64 m_nextId = 1;

  void applyRows(QVector<Row> rows);
};

}  // namespace heap::md
