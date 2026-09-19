#pragma once

#include <qqmlregistration.h>
#include <QQuickTextDocument>
#include <QSyntaxHighlighter>
#include <QTextCharFormat>
#include <QVariantMap>

namespace heap::md {

// Syntax highlighting for the notes editor.
//
// Replaces NotesHighlighter, which ran about twenty regular expressions
// against each line on its own. A line is not enough context for markdown:
// that highlighter could not tell a heading from a shell comment inside a
// fence, could not see a setext heading at all, and gave every heading level
// the same size, so a document's structure did not read at a glance.
//
// This one keeps a small state machine across lines — fences, frontmatter,
// display maths — and sizes headings by level. Inside a fenced block it hands
// the line to the same language rules the docs viewer uses, so a code block in
// a note looks like code rather than like tinted prose.
//
// It is deliberately lexical rather than AST-driven. A highlighter runs per
// line on every keystroke; a parse per keystroke of a large note would be felt
// as lag, and the AST is already available to everything that needs real
// structure.
class MdHighlighter : public QSyntaxHighlighter {
  Q_OBJECT
  QML_ELEMENT

  Q_PROPERTY(QQuickTextDocument* target READ target WRITE setTarget NOTIFY targetChanged)
  // Theme colours, by the same names NotesHighlighter used so the QML that
  // supplies them does not have to change.
  Q_PROPERTY(QVariantMap palette READ palette WRITE setPalette NOTIFY paletteChanged)
  // Relative size of an H1, with the levels below it scaled down toward 1.0.
  // 1.0 turns the effect off for anyone who would rather have an even page.
  Q_PROPERTY(qreal headingScale READ headingScale WRITE setHeadingScale NOTIFY headingScaleChanged)

 public:
  explicit MdHighlighter(QObject* parent = nullptr);

  QQuickTextDocument* target() const {
    return m_target;
  }

  void setTarget(QQuickTextDocument* target);

  QVariantMap palette() const {
    return m_palette;
  }

  void setPalette(const QVariantMap& palette);

  qreal headingScale() const {
    return m_headingScale;
  }

  void setHeadingScale(qreal scale);

 signals:
  void targetChanged();
  void paletteChanged();
  void headingScaleChanged();

 protected:
  void highlightBlock(const QString& text) override;

 private:
  // What a line can be in the middle of. previousBlockState carries it.
  enum BlockState {
    Normal = 0,
    InFence,
    InFrontmatter,
    InMathBlock,
  };

  void rebuildFormats();
  void highlightInline(const QString& text);
  void highlightCodeLine(const QString& text);

  QQuickTextDocument* m_target = nullptr;
  QVariantMap m_palette;
  qreal m_headingScale = 1.45;

  QTextCharFormat m_heading[6];
  QTextCharFormat m_code;
  QTextCharFormat m_codeFence;
  QTextCharFormat m_quote;
  QTextCharFormat m_marker;
  QTextCharFormat m_link;
  QTextCharFormat m_emphasis;
  QTextCharFormat m_strong;
  QTextCharFormat m_strike;
  QTextCharFormat m_taskDone;
  QTextCharFormat m_mention;
  QTextCharFormat m_ticket;
  QTextCharFormat m_tag;
  QTextCharFormat m_wiki;
  QTextCharFormat m_math;
  QTextCharFormat m_highlight;
  QTextCharFormat m_frontmatter;
  QTextCharFormat m_rule;
  QTextCharFormat m_table;

  // Language rules for whatever fence is currently open.
  QString m_fenceLanguage;
  QTextCharFormat m_codeKeyword;
  QTextCharFormat m_codeString;
  QTextCharFormat m_codeComment;
  QTextCharFormat m_codeNumber;
};

}  // namespace heap::md
