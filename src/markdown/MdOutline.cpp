#include "markdown/MdOutline.h"

#include <algorithm>
#include <functional>

namespace heap::md {

namespace {

// Concatenated text of an inline subtree, with markup dropped. A heading
// written as `## **Bold** title` reads as "Bold title", which is what a
// [[link]] to it spells and what an outline should show.
void appendPlainText(const MdAst& ast, int inlineIndex, QString* out) {
  if(inlineIndex < 0 || inlineIndex >= ast.inlines.size()) {
    return;
  }
  const MdInline& node = ast.inlines.at(inlineIndex);
  switch(node.type) {
    case InlineType::SoftBreak:
    case InlineType::HardBreak:
      *out += QLatin1Char(' ');
      break;
    case InlineType::HtmlInline:
      // Raw HTML is not text; dropping it keeps "<b>x</b>" from reading as
      // "<b>x</b>" in the outline.
      break;
    default:
      *out += node.text;
      break;
  }
  for(const int child : node.children) {
    appendPlainText(ast, child, out);
  }
}

QString plainText(const MdAst& ast, const MdBlock& block) {
  QString out;
  for(const int index : block.inlines) {
    appendPlainText(ast, index, &out);
  }
  return out.simplified();
}

// Walk every block, depth first, in document order. Headings and wiki links
// can sit inside quotes and list items, not only at the top level.
void visitBlocks(const MdAst& ast, int blockIndex, const std::function<void(const MdBlock&)>& fn) {
  if(blockIndex < 0 || blockIndex >= ast.blocks.size()) {
    return;
  }
  const MdBlock& block = ast.blocks.at(blockIndex);
  fn(block);
  for(const int child : block.children) {
    visitBlocks(ast, child, fn);
  }
}

}  // namespace

QVector<MdHeading> outline(const MdSourceMap& src, const MdAst& ast) {
  QVector<MdHeading> headings;
  if(!ast.isValid()) {
    return headings;
  }

  visitBlocks(ast, ast.root, [&](const MdBlock& block) {
    if(block.type != BlockType::Heading || !block.span.isValid()) {
      return;
    }
    MdHeading heading;
    heading.level = block.headingLevel;
    heading.text = plainText(ast, block);
    heading.line = block.span.firstLine;
    heading.utf16Offset = src.byteToUtf16(src.lineStartByte(block.span.firstLine));
    headings.append(heading);
  });

  std::sort(headings.begin(), headings.end(), [](const MdHeading& a, const MdHeading& b) {
    return a.line < b.line;
  });

  // A heading owns everything down to the next heading of the same or higher
  // rank: "## Two" ends at the next "##" or "#", not at a "###" beneath it.
  for(int i = 0; i < headings.size(); ++i) {
    headings[i].sectionFirstLine = headings.at(i).line;
    int last = src.lineCount() - 1;
    for(int j = i + 1; j < headings.size(); ++j) {
      if(headings.at(j).level <= headings.at(i).level) {
        last = headings.at(j).line - 1;
        break;
      }
    }
    headings[i].sectionLastLine = std::max(last, headings.at(i).line);
  }
  return headings;
}

QVector<MdSection> searchSections(const QString& markdown, int bodyCap) {
  const MdSourceMap src(markdown);
  const MdAst ast = parse(src);
  const QVector<MdHeading> headings = outline(src, ast);

  const auto capped = [bodyCap](QString text) {
    text = text.simplified();
    if(text.size() > bodyCap) {
      text.truncate(bodyCap);
    }
    return text;
  };

  QVector<MdSection> sections;

  // Anything above the first heading belongs to the note itself, not to a
  // section — losing it would make the top of a note unsearchable.
  const int firstHeadingLine = headings.isEmpty() ? src.lineCount() : headings.first().line;
  if(firstHeadingLine > 0) {
    const QString preamble = capped(src.textForLines(0, firstHeadingLine - 1));
    if(!preamble.isEmpty()) {
      sections.append(MdSection{QString(), preamble, 0});
    }
  }

  // Titles carry their ancestors, so a hit reads as "Release · Windows"
  // rather than as an isolated "Windows".
  QVector<MdHeading> trail;
  for(const MdHeading& heading : headings) {
    while(!trail.isEmpty() && trail.last().level >= heading.level) {
      trail.removeLast();
    }
    QStringList path;
    for(const MdHeading& ancestor : trail) {
      path << ancestor.text;
    }
    path << heading.text;
    trail.append(heading);

    sections.append(MdSection{
        path.join(QStringLiteral(" · ")), capped(src.textForLines(heading.sectionFirstLine, heading.sectionLastLine)), heading.line});
  }
  return sections;
}

QVector<MdWikiRef> wikiRefs(const MdSourceMap& src, const MdAst& ast) {
  QVector<MdWikiRef> refs;
  if(!ast.isValid()) {
    return refs;
  }

  // Only inline content is walked, so a [[link]] inside a fenced code block is
  // never seen: md4c reports that as code text, not as a wiki link.
  std::function<void(int, int)> visitInline = [&](int index, int fallbackLine) {
    if(index < 0 || index >= ast.inlines.size()) {
      return;
    }
    const MdInline& node = ast.inlines.at(index);
    if(node.type == InlineType::WikiLink) {
      const QString target = node.href.trimmed();
      if(!target.isEmpty()) {
        MdWikiRef ref;
        ref.target = target;
        // A wiki link's span is its target text, so the offset points inside
        // the brackets and a jump lands on the link rather than before it.
        // The enclosing block's first line is the fallback, which keeps a
        // reference reported on a sane line even if the span is missing.
        ref.line = node.span.isValid() ? node.span.firstLine : fallbackLine;
        ref.lineText = src.lineText(ref.line).trimmed();
        ref.utf16Offset = node.span.isValid() ? src.byteToUtf16(node.span.byteStart) : src.byteToUtf16(src.lineStartByte(ref.line));
        refs.append(ref);
      }
    }
    for(const int child : node.children) {
      visitInline(child, fallbackLine);
    }
  };

  visitBlocks(ast, ast.root, [&](const MdBlock& block) {
    const int fallbackLine = block.span.isValid() ? block.span.firstLine : 0;
    for(const int index : block.inlines) {
      visitInline(index, fallbackLine);
    }
  });

  std::sort(refs.begin(), refs.end(), [](const MdWikiRef& a, const MdWikiRef& b) {
    return a.utf16Offset < b.utf16Offset;
  });
  return refs;
}

}  // namespace heap::md
