#include "markdown/MdBlockModel.h"
#include "markdown/MdExtensions.h"

#include <algorithm>
#include <functional>

namespace heap::md {

namespace {

// State carried down the block tree while rows are produced. A row does not
// know it is inside a quote inside a list; it only knows how far in to sit and
// how many quote bars to draw to its left.
struct Context {
  int quoteDepth = 0;
  int indent = 0;
  QString marker;
  int taskState = -1;
  int taskLine = -1;
  bool loose = false;
  int topLevelBlock = -1;
};

QString bulletFor(int indent) {
  // Depth is shown by the glyph as well as by the indent, so a nested list
  // still reads as nested when it wraps.
  switch(indent % 3) {
    case 0:
      return QStringLiteral("•");
    case 1:
      return QStringLiteral("◦");
    default:
      return QStringLiteral("▪");
  }
}

bool isRemoteSource(const QString& source) {
  const QString lower = source.trimmed().toLower();
  return lower.startsWith(QStringLiteral("http://")) || lower.startsWith(QStringLiteral("https://")) ||
         lower.startsWith(QStringLiteral("//"));
}

// A paragraph whose whole content is one image is drawn as an image, not as a
// line of text with a picture in it.
const MdInline* soleImage(const MdAst& ast, const MdBlock& block) {
  const MdInline* image = nullptr;
  for(const int index : block.inlines) {
    if(index < 0 || index >= ast.inlines.size()) {
      continue;
    }
    const MdInline& node = ast.inlines.at(index);
    if(node.type == InlineType::Image) {
      if(image != nullptr) {
        return nullptr;  // more than one
      }
      image = &node;
      continue;
    }
    if(node.type == InlineType::Text && node.text.trimmed().isEmpty()) {
      continue;  // whitespace around it is fine
    }
    return nullptr;
  }
  return image;
}

}  // namespace

bool MdBlockModel::Row::sameContent(const Row& other) const {
  return type == other.type && html == other.html && level == other.level && language == other.language && code == other.code &&
         quoteDepth == other.quoteDepth && indent == other.indent && marker == other.marker && taskState == other.taskState &&
         calloutKind == other.calloutKind && calloutTitle == other.calloutTitle && startsFolded == other.startsFolded &&
         imageSource == other.imageSource && imageAlt == other.imageAlt && tableCells == other.tableCells &&
         tableColumns == other.tableColumns && footnoteId == other.footnoteId && footnoteNumber == other.footnoteNumber &&
         loose == other.loose;
}

MdBlockModel::MdBlockModel(QObject* parent) : QAbstractListModel(parent) {
}

int MdBlockModel::rowCount(const QModelIndex& parent) const {
  return parent.isValid() ? 0 : static_cast<int>(m_rows.size());
}

QHash<int, QByteArray> MdBlockModel::roleNames() const {
  return {
      {TypeRole, "rowType"},
      {HtmlRole, "html"},
      {PlainTextRole, "plainText"},
      {LevelRole, "level"},
      {LanguageRole, "language"},
      {CodeRole, "code"},
      {IsDiagramRole, "isDiagram"},
      {QuoteDepthRole, "quoteDepth"},
      {IndentRole, "indent"},
      {MarkerRole, "marker"},
      {TaskStateRole, "taskState"},
      {TaskLineRole, "taskLine"},
      {CalloutKindRole, "calloutKind"},
      {CalloutTitleRole, "calloutTitle"},
      {FoldableRole, "foldable"},
      {StartsFoldedRole, "startsFolded"},
      {ImageSourceRole, "imageSource"},
      {ImageAltRole, "imageAlt"},
      {ImageIsRemoteRole, "imageIsRemote"},
      {TableAlignRole, "tableAlign"},
      {TableCellsRole, "tableCells"},
      {TableColumnsRole, "tableColumns"},
      {TableHeaderRole, "tableHeaderCells"},
      {FootnoteIdRole, "footnoteId"},
      {FootnoteNumberRole, "footnoteNumber"},
      {LooseRole, "loose"},
      {FirstLineRole, "firstLine"},
      {LastLineRole, "lastLine"},
      {BlockIndexRole, "blockIndex"},
      {BlockIdRole, "blockId"},
  };
}

QVariant MdBlockModel::data(const QModelIndex& index, int role) const {
  if(!index.isValid() || index.row() < 0 || index.row() >= m_rows.size()) {
    return {};
  }
  const Row& row = m_rows.at(index.row());
  switch(role) {
    case TypeRole:
      return static_cast<int>(row.type);
    case HtmlRole:
      return row.html;
    case PlainTextRole:
      return row.plainText;
    case LevelRole:
      return row.level;
    case LanguageRole:
      return row.language;
    case CodeRole:
      return row.code;
    case IsDiagramRole:
      return row.isDiagram;
    case QuoteDepthRole:
      return row.quoteDepth;
    case IndentRole:
      return row.indent;
    case MarkerRole:
      return row.marker;
    case TaskStateRole:
      return row.taskState;
    case TaskLineRole:
      return row.taskLine;
    case CalloutKindRole:
      return row.calloutKind;
    case CalloutTitleRole:
      return row.calloutTitle;
    case FoldableRole:
      return row.foldable;
    case StartsFoldedRole:
      return row.startsFolded;
    case ImageSourceRole:
      return row.imageSource;
    case ImageAltRole:
      return row.imageAlt;
    case ImageIsRemoteRole:
      return row.imageIsRemote;
    case TableAlignRole:
      return row.tableAlign;
    case TableCellsRole:
      return row.tableCells;
    case TableColumnsRole:
      return row.tableColumns;
    case TableHeaderRole:
      return row.tableHeaderCells;
    case FootnoteIdRole:
      return row.footnoteId;
    case FootnoteNumberRole:
      return row.footnoteNumber;
    case LooseRole:
      return row.loose;
    case FirstLineRole:
      return row.firstLine;
    case LastLineRole:
      return row.lastLine;
    case BlockIndexRole:
      return row.blockIndex;
    case BlockIdRole:
      return static_cast<qulonglong>(row.id);
    default:
      return {};
  }
}

void MdBlockModel::setDocument(const MdSourceMap& src, const MdAst& ast, const MdHtmlOptions& options) {
  QVector<Row> rows;
  if(!ast.isValid()) {
    applyRows(rows);
    return;
  }

  // Collected while walking so the footnote section can be emitted last, the
  // way a reader expects to meet it.
  QVector<const MdBlock*> footnotes;

  std::function<void(int, Context)> visit = [&](int blockIndex, Context context) {
    if(blockIndex < 0 || blockIndex >= ast.blocks.size()) {
      return;
    }
    const MdBlock& block = ast.blocks.at(blockIndex);

    auto makeRow = [&](RowType type) {
      Row row;
      row.type = type;
      row.quoteDepth = context.quoteDepth;
      row.indent = context.indent;
      row.marker = context.marker;
      row.taskState = context.taskState;
      row.taskLine = context.taskLine;
      row.loose = context.loose;
      row.firstLine = block.span.isValid() ? block.span.firstLine : 0;
      row.lastLine = block.span.isValid() ? block.span.lastLine : row.firstLine;
      row.blockIndex = context.topLevelBlock;
      return row;
    };

    switch(block.type) {
      case BlockType::Document:
        for(const int child : block.children) {
          Context childContext = context;
          childContext.topLevelBlock = child;
          visit(child, childContext);
        }
        return;

      case BlockType::Quote: {
        Context inner = context;
        ++inner.quoteDepth;
        inner.marker.clear();
        inner.taskState = -1;
        for(const int child : block.children) {
          visit(child, inner);
        }
        return;
      }

      case BlockType::Callout: {
        Row header = makeRow(CalloutHeader);
        header.calloutKind = block.calloutKind;
        header.calloutTitle = block.calloutTitle;
        header.foldable = block.foldable;
        header.startsFolded = block.startsFolded;
        rows.append(header);

        Context inner = context;
        ++inner.quoteDepth;
        inner.marker.clear();
        for(const int child : block.children) {
          visit(child, inner);
        }
        return;
      }

      case BlockType::UnorderedList:
      case BlockType::OrderedList: {
        int number = block.listStart;
        for(const int child : block.children) {
          Context inner = context;
          ++inner.indent;
          inner.loose = !block.tight;
          inner.marker = block.type == BlockType::OrderedList ? QStringLiteral("%1.").arg(number++) : bulletFor(context.indent);
          const MdBlock& item = ast.blocks.at(child);
          inner.taskState = item.isTask ? (item.taskMark.toLower() == QChar(u'x') ? 1 : 0) : -1;
          inner.taskLine = item.isTask && item.span.isValid() ? item.span.firstLine : -1;
          visit(child, inner);
        }
        return;
      }

      case BlockType::ListItem: {
        Context inner = context;
        bool first = true;
        // A tight list item owns its text directly: md4c emits no paragraph
        // inside one, so without this the item would draw nothing at all.
        if(!block.inlines.isEmpty()) {
          Row row = makeRow(Paragraph);
          row.html = inlineHtml(ast, block, options);
          row.plainText = inlinePlainText(ast, block);
          rows.append(row);
          first = false;
        }
        for(const int child : block.children) {
          Context childContext = inner;
          if(!first) {
            // Only the first paragraph of an item gets the bullet; the rest
            // line up under it.
            childContext.marker.clear();
            childContext.taskState = -1;
          }
          visit(child, childContext);
          first = false;
        }
        return;
      }

      case BlockType::Paragraph: {
        if(const MdInline* image = soleImage(ast, block); image != nullptr) {
          Row row = makeRow(Image);
          row.imageSource = image->href;
          row.imageIsRemote = isRemoteSource(image->href);
          row.imageAlt = image->text.isEmpty() ? image->href : image->text;
          for(const int child : image->children) {
            row.imageAlt += ast.inlines.at(child).text;
          }
          rows.append(row);
          return;
        }
        Row row = makeRow(Paragraph);
        row.html = inlineHtml(ast, block, options);
        row.plainText = inlinePlainText(ast, block);
        rows.append(row);
        return;
      }

      case BlockType::Heading: {
        Row row = makeRow(Heading);
        row.level = block.headingLevel;
        row.html = inlineHtml(ast, block, options);
        row.plainText = inlinePlainText(ast, block);
        rows.append(row);
        return;
      }

      case BlockType::CodeBlock: {
        Row row = makeRow(Code);
        row.language = block.codeLanguage;
        row.isDiagram = isDiagramLanguage(block.codeLanguage);
        row.code = inlinePlainText(ast, block);
        // md4c ends each code line with its own break; the body is text, so it
        // is handed over verbatim rather than as rich text.
        while(row.code.endsWith(QLatin1Char('\n'))) {
          row.code.chop(1);
        }
        rows.append(row);
        return;
      }

      case BlockType::ThematicBreak:
        rows.append(makeRow(Rule));
        return;

      case BlockType::MathBlock: {
        Row row = makeRow(Math);
        row.code = src.textForLines(row.firstLine, row.lastLine);
        rows.append(row);
        return;
      }

      case BlockType::HtmlBlock: {
        Row row = makeRow(Html);
        row.code = src.textForLines(row.firstLine, row.lastLine);
        rows.append(row);
        return;
      }

      case BlockType::Frontmatter: {
        Row row = makeRow(Frontmatter);
        row.code = src.textForLines(row.firstLine, row.lastLine);
        rows.append(row);
        return;
      }

      case BlockType::FootnoteDef:
        footnotes.append(&block);
        return;

      case BlockType::Table: {
        Row row = makeRow(Table);
        row.tableColumns = block.columnCount;
        // Cells are flattened row-major: a GridLayout draws them directly, and
        // a table is small enough that this costs nothing.
        std::function<void(int, bool)> collect = [&](int index, bool header) {
          const MdBlock& cell = ast.blocks.at(index);
          switch(cell.type) {
            case BlockType::TableHead:
              for(const int child : cell.children) {
                collect(child, true);
              }
              break;
            case BlockType::TableBody:
            case BlockType::TableRow:
              for(const int child : cell.children) {
                collect(child, header);
              }
              break;
            case BlockType::TableHeaderCell:
            case BlockType::TableCell:
              if(header) {
                ++row.tableHeaderCells;
                if(row.tableAlign.size() < row.tableColumns) {
                  row.tableAlign.append(static_cast<int>(cell.align));
                }
              }
              row.tableCells.append(inlineHtml(ast, cell, options));
              break;
            default:
              break;
          }
        };
        for(const int child : block.children) {
          collect(child, false);
        }
        rows.append(row);
        return;
      }

      case BlockType::Opaque:
        // Source that draws nothing — a link reference definition. The row
        // exists so the model still covers every line.
        rows.append(makeRow(Blank));
        return;

      default:
        for(const int child : block.children) {
          visit(child, context);
        }
        return;
    }
  };

  visit(ast.root, Context{});

  if(!footnotes.isEmpty()) {
    Row heading;
    heading.type = FootnoteHeading;
    heading.firstLine = footnotes.first()->span.firstLine;
    heading.lastLine = heading.firstLine;
    heading.blockIndex = -1;
    rows.append(heading);

    for(const MdBlock* definition : footnotes) {
      Row row;
      row.type = FootnoteDef;
      row.footnoteId = definition->footnoteId;
      row.footnoteNumber = options.footnoteNumbers.value(definition->footnoteId, 0);
      row.html = inlineHtml(ast, *definition, options);
      row.plainText = inlinePlainText(ast, *definition);
      row.firstLine = definition->span.firstLine;
      row.lastLine = definition->span.lastLine;
      rows.append(row);
    }
  }

  applyRows(std::move(rows));
}

void MdBlockModel::applyRows(QVector<Row> rows) {
  // Rows that are unchanged keep their id, so a delegate that is already on
  // screen is reused. Typing in one paragraph must not rebuild the document.
  const int common = static_cast<int>(std::min(rows.size(), m_rows.size()));
  int prefix = 0;
  while(prefix < common && rows.at(prefix).sameContent(m_rows.at(prefix))) {
    rows[prefix].id = m_rows.at(prefix).id;
    ++prefix;
  }
  int suffix = 0;
  while(suffix < common - prefix && rows.at(rows.size() - 1 - suffix).sameContent(m_rows.at(m_rows.size() - 1 - suffix))) {
    rows[rows.size() - 1 - suffix].id = m_rows.at(m_rows.size() - 1 - suffix).id;
    ++suffix;
  }

  const int oldMiddle = static_cast<int>(m_rows.size()) - prefix - suffix;
  const int newMiddle = static_cast<int>(rows.size()) - prefix - suffix;

  for(int i = prefix; i < static_cast<int>(rows.size()) - suffix; ++i) {
    if(rows.at(i).id == 0) {
      rows[i].id = m_nextId++;
    }
  }

  if(oldMiddle == newMiddle && oldMiddle > 0) {
    // Same shape, different content: the view updates in place and keeps its
    // scroll position and any selection.
    m_rows = std::move(rows);
    emit dataChanged(index(prefix), index(prefix + newMiddle - 1));
    return;
  }

  if(oldMiddle > 0) {
    beginRemoveRows({}, prefix, prefix + oldMiddle - 1);
    m_rows.remove(prefix, oldMiddle);
    endRemoveRows();
  }
  if(newMiddle > 0) {
    beginInsertRows({}, prefix, prefix + newMiddle - 1);
    for(int i = 0; i < newMiddle; ++i) {
      m_rows.insert(prefix + i, rows.at(prefix + i));
    }
    endInsertRows();
  }
  // The untouched prefix and suffix are already correct by construction.
  for(int i = 0; i < prefix; ++i) {
    m_rows[i] = rows.at(i);
  }
  for(int i = 0; i < suffix; ++i) {
    m_rows[m_rows.size() - 1 - i] = rows.at(rows.size() - 1 - i);
  }
}

int MdBlockModel::rowForLine(int line) const {
  // The last row that starts at or before the line: rows are in document
  // order, and a row covers everything up to the next one.
  int best = -1;
  for(int i = 0; i < m_rows.size(); ++i) {
    if(m_rows.at(i).firstLine <= line) {
      best = i;
    } else {
      break;
    }
  }
  return best;
}

int MdBlockModel::firstLineOfRow(int row) const {
  return (row >= 0 && row < m_rows.size()) ? m_rows.at(row).firstLine : -1;
}

int MdBlockModel::lastLineOfRow(int row) const {
  return (row >= 0 && row < m_rows.size()) ? m_rows.at(row).lastLine : -1;
}

}  // namespace heap::md
