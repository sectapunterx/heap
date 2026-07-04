#include "NotesHighlighter.h"

#include <QColor>
#include <QQuickTextDocument>
#include <QTextDocument>

NotesHighlighter::NotesHighlighter(QObject* parent) : QSyntaxHighlighter(parent) {
  rebuildRules();
}

void NotesHighlighter::setTarget(QQuickTextDocument* t) {
  QTextDocument* newDoc = t ? t->textDocument() : nullptr;
  const bool targetChange = (m_target != t);
  const bool docChange = (document() != newDoc);
  if(!targetChange && !docChange) {
    return;
  }
  m_target = t;
  if(docChange) {
    setDocument(newDoc);
  }
  if(targetChange) {
    emit targetChanged();
  }
  if(document()) {
    rehighlight();
  }
}

void NotesHighlighter::setPalette(const QVariantMap& p) {
  if(m_palette == p) {
    return;
  }
  m_palette = p;
  emit paletteChanged();
  rebuildRules();
  if(document()) {
    rehighlight();
  }
}

QTextCharFormat NotesHighlighter::fmt(const char* key, bool bold, bool italic) const {
  QTextCharFormat f;
  const QVariant v = m_palette.value(QString::fromLatin1(key));
  auto c = v.value<QColor>();
  if(!c.isValid()) {
    // Sometimes QML hands us a QJSValue / QString instead of a QColor —
    // try parsing the string form before falling back to literals.
    const QString s = v.toString();
    if(!s.isEmpty()) {
      c = QColor(s);
    }
  }
  if(!c.isValid()) {
    // Sensible dark-mode fallbacks.
    const QByteArray k(key);
    if(k == "heading") {
      c = QColor("#8ad7ec");
    } else if(k == "bold") {
      c = QColor("#e5ecf3");
    } else if(k == "italic") {
      c = QColor("#e5ecf3");
    } else if(k == "code") {
      c = QColor("#d8c277");
    } else if(k == "codeBlock") {
      c = QColor("#d8c277");
    } else if(k == "quote") {
      c = QColor("#8a94a3");
    } else if(k == "mention") {
      c = QColor("#5aa3e6");
    } else if(k == "ticket") {
      c = QColor("#d8c277");
    } else if(k == "wikilink") {
      c = QColor("#b58ad7");
    } else if(k == "link") {
      c = QColor("#5cc2dd");
    } else if(k == "list") {
      c = QColor("#8a94a3");
    } else if(k == "tableRow") {
      c = QColor("#8ad7ec");
    } else if(k == "tableSep") {
      c = QColor("#5cc2dd");
    } else if(k == "latex") {
      c = QColor("#c07acf");
    } else if(k == "checkboxDone") {
      c = QColor("#6ec18a");
    } else if(k == "hr") {
      c = QColor("#323a48");
    } else {
      c = QColor("#e5ecf3");
    }
  }
  f.setForeground(c);
  if(bold) {
    f.setFontWeight(QFont::DemiBold);
  }
  if(italic) {
    f.setFontItalic(true);
  }
  return f;
}

void NotesHighlighter::rebuildRules() {
  m_rules.clear();

  // Block-level format used by the multiline state machine — fenced code
  // blocks paint the entire line with this format (forecolor + optional bg).
  {
    QTextCharFormat f = fmt("codeBlock");
    f.setFontFamilies({QStringLiteral("JetBrains Mono"), QStringLiteral("Fira Code"), QStringLiteral("DejaVu Sans Mono")});
    const QVariant bgv = m_palette.value(QStringLiteral("codeBlockBg"));
    auto bg = bgv.value<QColor>();
    if(!bg.isValid()) {
      const QString s = bgv.toString();
      if(!s.isEmpty()) {
        bg = QColor(s);
      }
    }
    if(!bg.isValid()) {
      bg = QColor("#0f131a");
    }
    f.setBackground(bg);
    m_codeBlockFmt = f;
  }

  // LaTeX block format — mono + accent colour, no background.
  {
    QTextCharFormat f = fmt("latex");
    f.setFontFamilies({QStringLiteral("JetBrains Mono"), QStringLiteral("Fira Code"), QStringLiteral("DejaVu Sans Mono")});
    m_latexFmt = f;
  }

  // --- Horizontal rule: ---  ***  ___  ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("^(?:-{3,}|\\*{3,}|_{3,})\\s*$"));
    r.format = fmt("hr", true);
    m_rules.push_back(r);
  }

  // --- Headings: # / ## / ### / #### / ##### / ###### ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("^#{1,6}\\s.+$"));
    r.format = fmt("heading", true);
    m_rules.push_back(r);
  }

  // --- Table separator row: |---|:---:|---:| ---
  // Must come before the generic table-row rule so the separator gets the
  // stronger format (rule order is paint order — later rules win on overlap,
  // but both are full-line matches, so we keep this declaration first and
  // overwrite with the row rule below).
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("^\\s*\\|?\\s*:?-{3,}:?\\s*(?:\\|\\s*:?-{3,}:?\\s*)+\\|?\\s*$"));
    r.format = fmt("tableSep", true);
    m_rules.push_back(r);
  }

  // --- Table row: any line that contains a pipe between non-pipe chars ---
  // The separator rule above paints the dashes; the row rule re-paints any
  // other pipe-delimited line. Order matters — separator must come first so
  // its format isn't clobbered when the row pattern matches it too.
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("^\\s*\\|[^\\n]*\\|\\s*$"));
    r.format = fmt("tableRow");
    m_rules.push_back(r);
  }

  // --- Checklist done: - [x] / * [X] / + [x] ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("^\\s*[-*+]\\s+\\[[xX]\\]\\s+.*$"));
    QTextCharFormat f = fmt("checkboxDone");
    f.setFontStrikeOut(true);
    r.format = f;
    m_rules.push_back(r);
  }

  // --- Checklist todo: - [ ] / * [ ] / + [ ] (marker portion only) ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("^\\s*[-*+]\\s+\\[\\s\\]"));
    r.format = fmt("list", true);
    m_rules.push_back(r);
  }

  // --- List markers (the dash, not the whole line) ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("^\\s*([-*+])\\s"));
    r.format = fmt("list", true);
    r.captureGroup = 1;
    m_rules.push_back(r);
  }

  // --- Numbered list markers: "1. " "12. " ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("^\\s*(\\d+\\.)\\s"));
    r.format = fmt("list", true);
    r.captureGroup = 1;
    m_rules.push_back(r);
  }

  // --- Quote block ">" ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("^\\s*>+\\s.*$"));
    r.format = fmt("quote", false, true);
    m_rules.push_back(r);
  }

  // --- Markdown link [text](url) — color the whole match ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("\\[[^\\]\\n]+\\]\\([^)\\n]+\\)"));
    QTextCharFormat f = fmt("link");
    f.setFontUnderline(true);
    r.format = f;
    m_rules.push_back(r);
  }

  // --- Strike-through ~~text~~ ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("~~[^~\\n]+~~"));
    QTextCharFormat f = fmt("quote");
    f.setFontStrikeOut(true);
    r.format = f;
    m_rules.push_back(r);
  }

  // --- Bold **text** ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("\\*\\*[^*\\n]+\\*\\*"));
    r.format = fmt("bold", true);
    m_rules.push_back(r);
  }

  // --- Italic *text* (avoid eating the inside of **bold**) ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("(?<![*\\w])\\*(?!\\s)[^*\\n]+\\*(?!\\w)"));
    r.format = fmt("italic", false, true);
    m_rules.push_back(r);
  }

  // --- Inline code `code` ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("`[^`\\n]+`"));
    QTextCharFormat f = fmt("code");
    f.setFontFamilies({QStringLiteral("JetBrains Mono"), QStringLiteral("Fira Code"), QStringLiteral("DejaVu Sans Mono")});
    // Subtle background — derived from "codeBg" if present, otherwise leave bare.
    const QVariant bgv = m_palette.value(QStringLiteral("codeBg"));
    const auto bg = bgv.value<QColor>();
    if(bg.isValid()) {
      f.setBackground(bg);
    }
    r.format = f;
    m_rules.push_back(r);
  }

  // --- @mention ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("(?<![A-Za-z0-9_])@[A-Za-z0-9_.\\-]+"));
    r.format = fmt("mention", true);
    m_rules.push_back(r);
  }

  // --- #TICKET-id (e.g. LTE-2401) ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("(?<![A-Za-z0-9_])#[A-Z][A-Z0-9]*-\\d+"));
    r.format = fmt("ticket", true);
    m_rules.push_back(r);
  }

  // --- [[wiki-link]] to a note heading (HEAP-79) ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("\\[\\[[^\\]\\n]+\\]\\]"));
    r.format = fmt("wikilink", true);
    m_rules.push_back(r);
  }

  // --- Inline LaTeX: $...$ (single line). Skip $$ (block fence) and \$. ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("(?<![\\\\$])\\$(?!\\$)[^\\$\\n]+\\$(?!\\$)"));
    QTextCharFormat f = fmt("latex");
    f.setFontFamilies({QStringLiteral("JetBrains Mono"), QStringLiteral("Fira Code"), QStringLiteral("DejaVu Sans Mono")});
    r.format = f;
    m_rules.push_back(r);
  }

  // --- Image source ![alt](url) — same look as a link plus a leading bang. ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("!\\[[^\\]\\n]*\\]\\([^)\\n]+\\)"));
    QTextCharFormat f = fmt("link");
    f.setFontUnderline(false);
    f.setFontItalic(true);
    r.format = f;
    m_rules.push_back(r);
  }

  // --- Bare URL auto-link http(s):// up to whitespace. ---
  {
    Rule r;
    r.pattern = QRegularExpression(QStringLiteral("\\bhttps?://[^\\s)\\]]+"));
    QTextCharFormat f = fmt("link");
    f.setFontUnderline(true);
    r.format = f;
    m_rules.push_back(r);
  }
}

void NotesHighlighter::highlightBlock(const QString& text) {
  // Block state machine — handles multi-line fenced code (```) and LaTeX
  // ($$ ... $$) blocks. previousBlockState() / setCurrentBlockState() keep
  // the parser stateful across paragraph boundaries.
  const int prev = previousBlockState();
  const bool inFence = (prev == BS_FencedCode);
  const bool inLatex = (prev == BS_LatexBlock);
  const QString trimmed = text.trimmed();

  // Fenced ``` open / close — paint the fence line + toggle state.
  if(trimmed.startsWith(QStringLiteral("```"))) {
    if(text.length() > 0) {
      setFormat(0, text.length(), m_codeBlockFmt);
    }
    setCurrentBlockState(inFence ? BS_Normal : BS_FencedCode);
    return;
  }
  if(inFence) {
    if(text.length() > 0) {
      setFormat(0, text.length(), m_codeBlockFmt);
    }
    setCurrentBlockState(BS_FencedCode);
    return;
  }

  // LaTeX $$ open / close — same state-toggle pattern.
  if(trimmed == QStringLiteral("$$") || (trimmed.startsWith(QStringLiteral("$$")) && trimmed.length() > 2 && !inLatex) ||
     (trimmed.endsWith(QStringLiteral("$$")) && inLatex)) {
    if(text.length() > 0) {
      setFormat(0, text.length(), m_latexFmt);
    }
    setCurrentBlockState(inLatex ? BS_Normal : BS_LatexBlock);
    return;
  }
  if(inLatex) {
    if(text.length() > 0) {
      setFormat(0, text.length(), m_latexFmt);
    }
    setCurrentBlockState(BS_LatexBlock);
    return;
  }

  setCurrentBlockState(BS_Normal);

  for(const Rule& r : m_rules) {
    auto it = r.pattern.globalMatch(text);
    while(it.hasNext()) {
      const auto m = it.next();
      const int start = m.capturedStart(r.captureGroup);
      const int len = m.capturedLength(r.captureGroup);
      if(len > 0) {
        setFormat(start, len, r.format);
      }
    }
  }
}
