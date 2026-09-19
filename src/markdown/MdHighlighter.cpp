#include "markdown/MdHighlighter.h"

#include <QRegularExpression>
#include <QTextDocument>

namespace heap::md {

namespace {

QColor colorAt(const QVariantMap& palette, const char* key, const QColor& fallback) {
  const QVariant value = palette.value(QLatin1String(key));
  if(!value.isValid()) {
    return fallback;
  }
  const QColor color = value.value<QColor>();
  return color.isValid() ? color : fallback;
}

// A fence opens with three or more backticks or tildes; the info string after
// it names the language.
const QRegularExpression& fenceRx() {
  static const QRegularExpression rx(QStringLiteral("^\\s{0,3}(`{3,}|~{3,})\\s*([A-Za-z0-9_+#.-]*)"));
  return rx;
}

const QRegularExpression& atxHeadingRx() {
  static const QRegularExpression rx(QStringLiteral("^\\s{0,3}(#{1,6})(\\s+.*)?$"));
  return rx;
}

// A line of only = or - under text makes that text a heading. A per-line
// highlighter cannot see the text above it, but it can at least mark the
// underline, which is what the old one missed entirely.
const QRegularExpression& setextRx() {
  static const QRegularExpression rx(QStringLiteral("^\\s{0,3}(={2,}|-{2,})\\s*$"));
  return rx;
}

const QRegularExpression& thematicBreakRx() {
  static const QRegularExpression rx(QStringLiteral("^\\s{0,3}(?:-\\s*){3,}$|^\\s{0,3}(?:\\*\\s*){3,}$|^\\s{0,3}(?:_\\s*){3,}$"));
  return rx;
}

const QRegularExpression& listMarkerRx() {
  static const QRegularExpression rx(QStringLiteral("^(\\s*)([-*+]|\\d+[.)])(\\s+)(\\[([ xX])\\]\\s+)?"));
  return rx;
}

const QRegularExpression& quoteRx() {
  static const QRegularExpression rx(QStringLiteral("^\\s*(?:>\\s?)+"));
  return rx;
}

const QRegularExpression& tableRowRx() {
  static const QRegularExpression rx(QStringLiteral("^\\s*\\|.*\\|\\s*$"));
  return rx;
}

}  // namespace

MdHighlighter::MdHighlighter(QObject* parent) : QSyntaxHighlighter(parent) {
  rebuildFormats();
}

void MdHighlighter::setTarget(QQuickTextDocument* target) {
  if(m_target == target) {
    return;
  }
  m_target = target;
  setDocument(target != nullptr ? target->textDocument() : nullptr);
  emit targetChanged();
}

void MdHighlighter::setPalette(const QVariantMap& palette) {
  if(m_palette == palette) {
    return;
  }
  m_palette = palette;
  rebuildFormats();
  rehighlight();
  emit paletteChanged();
}

void MdHighlighter::setHeadingScale(qreal scale) {
  if(qFuzzyCompare(m_headingScale, scale)) {
    return;
  }
  m_headingScale = scale;
  rebuildFormats();
  rehighlight();
  emit headingScaleChanged();
}

void MdHighlighter::rebuildFormats() {
  const QColor text = colorAt(m_palette, "text", QColor(0xE6, 0xE6, 0xE6));
  const QColor dim = colorAt(m_palette, "dim", QColor(0x8A, 0x8E, 0x98));
  const QColor accent = colorAt(m_palette, "accent", QColor(0x5A, 0xC8, 0xD8));
  const QColor codeColor = colorAt(m_palette, "code", text);
  const QColor codeBg = colorAt(m_palette, "codeBg", QColor());

  // Headings: the level shows in the weight here, and in the size applied per
  // line in highlightBlock. Sizing relative to the document's own font keeps
  // the editor's font setting as the baseline instead of hard-coding points.
  for(int level = 0; level < 6; ++level) {
    m_heading[level].setFontWeight(level <= 2 ? QFont::Bold : QFont::DemiBold);
    m_heading[level].setForeground(text);
  }

  m_code.setForeground(codeColor);
  m_code.setFontFixedPitch(true);
  if(codeBg.isValid()) {
    m_code.setBackground(codeBg);
  }
  m_codeFence = m_code;
  m_codeFence.setForeground(dim);

  m_quote.setForeground(dim);
  m_quote.setFontItalic(true);
  m_marker.setForeground(accent);
  m_marker.setFontWeight(QFont::DemiBold);
  m_link.setForeground(accent);
  m_link.setFontUnderline(true);
  m_emphasis.setFontItalic(true);
  m_strong.setFontWeight(QFont::Bold);
  m_strike.setFontStrikeOut(true);
  m_strike.setForeground(dim);
  m_taskDone.setFontStrikeOut(true);
  m_taskDone.setForeground(dim);
  m_mention.setForeground(colorAt(m_palette, "mention", accent));
  m_ticket.setForeground(colorAt(m_palette, "ticket", accent));
  m_ticket.setFontWeight(QFont::DemiBold);
  m_tag.setForeground(colorAt(m_palette, "tag", accent));
  m_wiki.setForeground(accent);
  m_math.setForeground(colorAt(m_palette, "math", accent));
  m_math.setFontFixedPitch(true);
  m_highlight.setBackground(colorAt(m_palette, "highlightBg", QColor(0, 0, 0, 0)));
  m_frontmatter.setForeground(dim);
  m_frontmatter.setFontFixedPitch(true);
  m_rule.setForeground(dim);
  m_table.setForeground(dim);

  // Fenced code uses the same colours the docs viewer already speaks, so a
  // snippet looks the same wherever it is read.
  m_codeKeyword.setForeground(colorAt(m_palette, "keyword", accent));
  m_codeKeyword.setFontWeight(QFont::DemiBold);
  m_codeString.setForeground(colorAt(m_palette, "string", QColor(0x9C, 0xC4, 0x8B)));
  m_codeComment.setForeground(dim);
  m_codeComment.setFontItalic(true);
  m_codeNumber.setForeground(colorAt(m_palette, "number", QColor(0xD8, 0xC2, 0x77)));
}

void MdHighlighter::highlightCodeLine(const QString& text) {
  setFormat(0, static_cast<int>(text.size()), m_code);
  if(text.isEmpty()) {
    return;
  }

  // Deliberately coarse: strings, comments and numbers, plus a handful of
  // words every language in a note is likely to use. A note is not an IDE,
  // and a per-keystroke highlighter cannot afford a real lexer per language.
  static const QRegularExpression stringRx(QStringLiteral("\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'|`(?:[^`\\\\\\n]|\\\\.)*`"));
  static const QRegularExpression numberRx(QStringLiteral("\\b\\d+(?:\\.\\d+)?\\b"));
  static const QRegularExpression commentRx(QStringLiteral("(//|#|--)[^\\n]*$"));
  static const QRegularExpression keywordRx(
      QStringLiteral("\\b(?:if|else|for|while|return|class|struct|def|function|fn|let|const|var|import|from|"
                     "include|namespace|public|private|protected|static|void|int|bool|true|false|null|nullptr|"
                     "None|True|False|async|await|try|catch|except|finally|throw|raise|new|delete|this|self)\\b"));

  auto apply = [&](const QRegularExpression& rx, const QTextCharFormat& format) {
    auto it = rx.globalMatch(text);
    while(it.hasNext()) {
      const auto match = it.next();
      setFormat(static_cast<int>(match.capturedStart()), static_cast<int>(match.capturedLength()), format);
    }
  };

  apply(keywordRx, m_codeKeyword);
  apply(numberRx, m_codeNumber);
  // Strings and comments come last so a keyword inside one is not recoloured.
  apply(stringRx, m_codeString);
  apply(commentRx, m_codeComment);
}

void MdHighlighter::highlightInline(const QString& text) {
  struct Rule {
    const QRegularExpression* pattern;
    const QTextCharFormat* format;
    int group;
  };

  static const QRegularExpression codeRx(QStringLiteral("`[^`\\n]+`"));
  static const QRegularExpression strongRx(QStringLiteral("\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__"));
  static const QRegularExpression emphasisRx(QStringLiteral("(?<![*\\w])\\*(?!\\s)[^*\\n]+\\*(?!\\w)|(?<![_\\w])_(?!\\s)[^_\\n]+_(?!\\w)"));
  static const QRegularExpression strikeRx(QStringLiteral("~~[^~\\n]+~~"));
  static const QRegularExpression highlightRx(QStringLiteral("==[^=\\n]+=="));
  static const QRegularExpression linkRx(QStringLiteral("!?\\[[^\\]\\n]*\\]\\([^)\\n]*\\)"));
  static const QRegularExpression wikiRx(QStringLiteral("\\[\\[[^\\]\\n]+\\]\\]"));
  static const QRegularExpression urlRx(QStringLiteral("\\bhttps?://[^\\s)\\]]+"));
  static const QRegularExpression mathRx(QStringLiteral("(?<![\\\\$])\\$(?!\\s)[^$\\n]+\\$(?!\\$)"));
  static const QRegularExpression mentionRx(QStringLiteral("(?<![A-Za-z0-9_])@[A-Za-z0-9_.-]+"));
  static const QRegularExpression ticketRx(QStringLiteral("(?<![A-Za-z0-9_])#[A-Z][A-Z0-9]*-\\d+"));
  static const QRegularExpression tagRx(QStringLiteral("(?<![A-Za-z0-9_])#[A-Za-z][A-Za-z0-9_/-]*"));
  static const QRegularExpression footnoteRx(QStringLiteral("\\[\\^[^\\]\\s]+\\]"));

  const Rule rules[] = {
      {&strongRx, &m_strong, 0},
      {&emphasisRx, &m_emphasis, 0},
      {&strikeRx, &m_strike, 0},
      {&highlightRx, &m_highlight, 0},
      {&wikiRx, &m_wiki, 0},
      {&linkRx, &m_link, 0},
      {&urlRx, &m_link, 0},
      {&mathRx, &m_math, 0},
      {&ticketRx, &m_ticket, 0},
      {&tagRx, &m_tag, 0},
      {&mentionRx, &m_mention, 0},
      {&footnoteRx, &m_wiki, 0},
  };

  for(const Rule& rule : rules) {
    auto it = rule.pattern->globalMatch(text);
    while(it.hasNext()) {
      const auto match = it.next();
      setFormat(static_cast<int>(match.capturedStart(rule.group)), static_cast<int>(match.capturedLength(rule.group)), *rule.format);
    }
  }

  // Inline code last: what is inside backticks is not markdown, so nothing
  // else should have coloured it. "#tag" in a snippet is a comment.
  auto it = codeRx.globalMatch(text);
  while(it.hasNext()) {
    const auto match = it.next();
    setFormat(static_cast<int>(match.capturedStart()), static_cast<int>(match.capturedLength()), m_code);
  }
}

void MdHighlighter::highlightBlock(const QString& text) {
  const int previous = previousBlockState();
  const int length = static_cast<int>(text.size());

  // ── Multi-line state ────────────────────────────────────────────
  // A line on its own cannot tell code from prose, which is what the old
  // per-line highlighter got wrong.
  if(previous == InFrontmatter) {
    setFormat(0, length, m_frontmatter);
    setCurrentBlockState(text.trimmed() == QStringLiteral("---") || text.trimmed() == QStringLiteral("...") ? Normal : InFrontmatter);
    return;
  }
  if(currentBlock().blockNumber() == 0 && text.trimmed() == QStringLiteral("---")) {
    setFormat(0, length, m_frontmatter);
    setCurrentBlockState(InFrontmatter);
    return;
  }

  if(previous == InFence) {
    const auto fence = fenceRx().match(text);
    if(fence.hasMatch() && fence.captured(2).isEmpty()) {
      setFormat(0, length, m_codeFence);
      setCurrentBlockState(Normal);
      return;
    }
    highlightCodeLine(text);
    setCurrentBlockState(InFence);
    return;
  }

  if(previous == InMathBlock) {
    setFormat(0, length, m_math);
    setCurrentBlockState(text.trimmed() == QStringLiteral("$$") ? Normal : InMathBlock);
    return;
  }

  const auto fence = fenceRx().match(text);
  if(fence.hasMatch()) {
    setFormat(0, length, m_codeFence);
    m_fenceLanguage = fence.captured(2);
    setCurrentBlockState(InFence);
    return;
  }
  if(text.trimmed() == QStringLiteral("$$")) {
    setFormat(0, length, m_math);
    setCurrentBlockState(InMathBlock);
    return;
  }

  setCurrentBlockState(Normal);

  // ── Line-level structure ────────────────────────────────────────
  const auto heading = atxHeadingRx().match(text);
  if(heading.hasMatch()) {
    const int level = static_cast<int>(heading.captured(1).size());
    QTextCharFormat format = m_heading[std::clamp(level, 1, 6) - 1];
    // Qt stores a heading's relative size as a multiplier on the document's
    // default font; setting it here keeps the editor's own font setting as the
    // baseline instead of hard-coding point sizes.
    format.setProperty(QTextFormat::FontSizeAdjustment, static_cast<int>(std::round((m_headingScale - 1.0) * (7 - level))));
    setFormat(0, length, format);
    highlightInline(text);
    return;
  }

  if(setextRx().match(text).hasMatch() && currentBlock().blockNumber() > 0 && !currentBlock().previous().text().trimmed().isEmpty()) {
    // The underline of a setext heading. The old highlighter saw nothing here
    // at all, so such a heading looked like ordinary text with a rule under it.
    setFormat(0, length, m_heading[0]);
    return;
  }

  if(thematicBreakRx().match(text).hasMatch()) {
    setFormat(0, length, m_rule);
    return;
  }

  if(tableRowRx().match(text).hasMatch()) {
    setFormat(0, length, m_table);
    highlightInline(text);
    return;
  }

  const auto quote = quoteRx().match(text);
  if(quote.hasMatch() && quote.capturedLength() > 0) {
    setFormat(0, length, m_quote);
    setFormat(0, static_cast<int>(quote.capturedLength()), m_marker);
    highlightInline(text);
    return;
  }

  const auto list = listMarkerRx().match(text);
  if(list.hasMatch()) {
    setFormat(static_cast<int>(list.capturedStart(2)), static_cast<int>(list.capturedLength(2)), m_marker);
    if(!list.captured(4).isEmpty()) {
      setFormat(static_cast<int>(list.capturedStart(4)), static_cast<int>(list.capturedLength(4)), m_marker);
      // A finished task reads as finished, the way it does in the rendered
      // view.
      if(list.captured(5).toLower() == QStringLiteral("x")) {
        setFormat(static_cast<int>(list.capturedEnd(4)), length - static_cast<int>(list.capturedEnd(4)), m_taskDone);
      }
    }
  }

  highlightInline(text);
}

}  // namespace heap::md
