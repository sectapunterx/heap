#include "markdown/MdExtensions.h"

#include <QRegularExpression>

namespace heap::md {

namespace {

// "> [!NOTE]", "> [!warning]-", "> [!TIP]+ Custom title". The marker sits on
// the quote's first line, after however many "> " markers nest it.
const QRegularExpression& calloutRx() {
  static const QRegularExpression rx(QStringLiteral("^\\s*(?:>\\s*)+\\[!([A-Za-z][A-Za-z0-9_-]*)\\]([+-]?)\\s*(.*)$"));
  return rx;
}

// Remove `count` characters from the start of a block's inline text, walking
// across nodes: md4c splits a run like "[!NOTE] title" into several text
// chunks, so the marker rarely lives in a single one.
void stripLeadingCharacters(MdAst* ast, const MdBlock& block, int count) {
  for(const int index : block.inlines) {
    if(count <= 0) {
      return;
    }
    MdInline& node = (*ast).inlines[index];
    if(node.type != InlineType::Text) {
      // Anything other than plain text means the marker is already past.
      return;
    }
    const int take = std::min(count, static_cast<int>(node.text.size()));
    node.text.remove(0, take);
    count -= take;
  }
}

// The first descendant paragraph of a block, or -1. A callout's title lives in
// the quote's first paragraph, which may be nested one level down.
int firstParagraph(const MdAst& ast, int blockIndex) {
  if(blockIndex < 0 || blockIndex >= ast.blocks.size()) {
    return -1;
  }
  const MdBlock& block = ast.blocks.at(blockIndex);
  if(block.type == BlockType::Paragraph) {
    return blockIndex;
  }
  for(const int child : block.children) {
    const int found = firstParagraph(ast, child);
    if(found >= 0) {
      return found;
    }
  }
  return -1;
}

void detectCallout(const MdSourceMap& src, MdAst* ast, int blockIndex) {
  MdBlock& block = (*ast).blocks[blockIndex];
  if(block.type != BlockType::Quote || !block.span.isValid()) {
    return;
  }
  const auto match = calloutRx().match(src.lineText(block.span.firstLine));
  if(!match.hasMatch()) {
    return;
  }

  block.type = BlockType::Callout;
  block.calloutKind = match.captured(1).toLower();
  const QString fold = match.captured(2);
  block.foldable = !fold.isEmpty();
  block.startsFolded = fold == QStringLiteral("-");

  // A title after the marker wins; otherwise the kind names the callout, which
  // is what every editor that supports these does.
  const QString title = match.captured(3).trimmed();
  block.calloutTitle = title.isEmpty() ? block.calloutKind : title;

  // Drop "[!KIND]" and its fold marker from the rendered text, so the body
  // does not repeat the header. Everything after it on that line is the title
  // and is dropped from the body too.
  const int paragraph = firstParagraph(*ast, blockIndex);
  if(paragraph >= 0) {
    const int markerLength = match.capturedEnd(2) - match.capturedStart(1) + 2;  // "[!" … "]" + fold
    stripLeadingCharacters(ast, ast->blocks.at(paragraph), markerLength + title.size());
  }
}

void detectMathBlock(MdAst* ast, int blockIndex) {
  MdBlock& block = (*ast).blocks[blockIndex];
  if(block.type != BlockType::Paragraph || block.inlines.size() != 1) {
    return;
  }
  if(ast->inlines.at(block.inlines.at(0)).type == InlineType::LatexMathDisplay) {
    block.type = BlockType::MathBlock;
  }
}

void visit(const MdSourceMap& src, MdAst* ast, int blockIndex) {
  if(blockIndex < 0 || blockIndex >= ast->blocks.size()) {
    return;
  }
  // Children are collected first: detectCallout rewrites the block it is given
  // but never its children, so order is not load-bearing — copying the list
  // keeps it safe if that ever changes.
  const QVector<int> children = ast->blocks.at(blockIndex).children;

  detectCallout(src, ast, blockIndex);
  detectMathBlock(ast, blockIndex);

  for(const int child : children) {
    visit(src, ast, child);
  }
}

}  // namespace

void applyExtensions(const MdSourceMap& src, MdAst* ast) {
  if(ast == nullptr || !ast->isValid()) {
    return;
  }
  visit(src, ast, ast->root);
}

bool isDiagramLanguage(const QString& language) {
  const QString lower = language.trimmed().toLower();
  return lower == QStringLiteral("mermaid") || lower == QStringLiteral("plantuml") || lower == QStringLiteral("dot") ||
         lower == QStringLiteral("graphviz");
}

}  // namespace heap::md
