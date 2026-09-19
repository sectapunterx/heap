#include "markdown/MdDocument.h"

#include <QElapsedTimer>
#include <QTextCursor>
#include <QTextDocument>
#include <QVariantMap>

#include <algorithm>

namespace heap::md {

namespace {

// Typing must never wait for markdown. A small note is parsed as the key is
// released; a large one waits, and waits longer the slower the last parse was,
// so the delay scales with the document rather than being guessed once.
constexpr int kMaxDebounceMs = 300;
constexpr int kSynchronousBudgetMs = 8;

QString colorAt(const QVariantMap& palette, const char* key) {
  return palette.value(QLatin1String(key)).toString();
}

}  // namespace

MdDocument::MdDocument(QObject* parent) : QObject(parent) {
  m_parseTimer.setSingleShot(true);
  connect(&m_parseTimer, &QTimer::timeout, this, &MdDocument::reparse);
}

void MdDocument::setText(const QString& text) {
  if(m_text == text) {
    return;
  }
  m_text = text;
  m_dirty = true;
  emit textChanged();
  scheduleParse();
}

void MdDocument::setPalette(const QVariantMap& palette) {
  if(m_palette == palette) {
    return;
  }
  m_palette = palette;
  emit paletteChanged();
  // Colours are baked into the rendered rows, so a theme change is a reparse.
  m_dirty = true;
  reparse();
}

void MdDocument::setAllowRemoteImages(bool allow) {
  if(m_allowRemoteImages == allow) {
    return;
  }
  m_allowRemoteImages = allow;
  emit allowRemoteImagesChanged();
  m_dirty = true;
  reparse();
}

void MdDocument::scheduleParse() {
  if(m_lastParseMs <= kSynchronousBudgetMs) {
    reparse();
    return;
  }
  m_parseTimer.start(std::min(2 * m_lastParseMs, kMaxDebounceMs));
}

void MdDocument::flush() {
  if(m_dirty) {
    reparse();
  }
}

MdHtmlOptions MdDocument::buildOptions() const {
  MdHtmlOptions options;
  options.palette.text = colorAt(m_palette, "text");
  options.palette.dim = colorAt(m_palette, "dim");
  options.palette.link = colorAt(m_palette, "link");
  options.palette.code = colorAt(m_palette, "code");
  options.palette.codeBackground = colorAt(m_palette, "codeBackground");
  options.palette.highlightBackground = colorAt(m_palette, "highlightBackground");
  options.palette.mention = colorAt(m_palette, "mention");
  options.palette.ticket = colorAt(m_palette, "ticket");
  options.palette.tag = colorAt(m_palette, "tag");
  options.palette.math = colorAt(m_palette, "math");
  options.allowRemoteImages = m_allowRemoteImages;
  return options;
}

void MdDocument::reparse() {
  m_parseTimer.stop();
  m_dirty = false;

  QElapsedTimer timer;
  timer.start();

  m_src = MdSourceMap(m_text);
  m_ast = parse(m_src);

  MdHtmlOptions options = buildOptions();
  options.footnoteNumbers = footnoteNumbers(m_ast);
  m_model.setDocument(m_src, m_ast, options);

  m_outline.clear();
  for(const MdHeading& heading : outline(m_src, m_ast)) {
    if(heading.text.isEmpty()) {
      continue;
    }
    QVariantMap entry;
    entry.insert(QStringLiteral("level"), heading.level);
    entry.insert(QStringLiteral("text"), heading.text);
    entry.insert(QStringLiteral("line"), heading.line);
    entry.insert(QStringLiteral("offset"), heading.utf16Offset);
    entry.insert(QStringLiteral("sectionFirstLine"), heading.sectionFirstLine);
    entry.insert(QStringLiteral("sectionLastLine"), heading.sectionLastLine);
    m_outline.append(entry);
  }

  m_lastParseMs = static_cast<int>(timer.elapsed());
  emit parsed();
}

int MdDocument::rowForLine(int line) {
  flush();
  return m_model.rowForLine(line);
}

int MdDocument::firstLineOfRow(int row) {
  flush();
  return m_model.firstLineOfRow(row);
}

int MdDocument::lastLineOfRow(int row) {
  flush();
  return m_model.lastLineOfRow(row);
}

int MdDocument::lineForPosition(int position) {
  flush();
  return m_src.lineOfByte(m_src.utf16ToByte(position));
}

int MdDocument::positionForLine(int line) {
  flush();
  return m_src.byteToUtf16(m_src.lineStartByte(line));
}

bool MdDocument::toggleTask(QQuickTextDocument* target, int row) {
  if(target == nullptr || target->textDocument() == nullptr) {
    return false;
  }
  const QVariantMap edit = taskToggleForRow(row);
  if(edit.isEmpty()) {
    return false;
  }

  const int position = edit.value(QStringLiteral("position")).toInt();
  const QString to = edit.value(QStringLiteral("to")).toString();

  QTextCursor cursor(target->textDocument());
  cursor.setPosition(position);
  cursor.movePosition(QTextCursor::NextCharacter, QTextCursor::KeepAnchor);
  if(cursor.selectedText() != edit.value(QStringLiteral("from")).toString()) {
    // The document moved under us between the parse and the click.
    return false;
  }

  // One edit block, so Ctrl+Z takes the whole change back. As a remove
  // followed by an insert this looked identical until undo, which reverted
  // only the insert and left "[]" behind — no longer a task at all.
  cursor.beginEditBlock();
  cursor.insertText(to);
  cursor.endEditBlock();
  return true;
}

QVariantMap MdDocument::taskToggleForRow(int row) {
  flush();
  const int line = m_model.data(m_model.index(row), MdBlockModel::TaskLineRole).toInt();
  if(line < 0) {
    return {};
  }

  // Find the item whose own first line is this one, and take the offset md4c
  // reported for the character between its brackets.
  for(const MdBlock& block : m_ast.blocks) {
    if(block.type != BlockType::ListItem || !block.isTask || block.taskMarkByte < 0) {
      continue;
    }
    if(!block.span.isValid() || block.span.firstLine != line) {
      continue;
    }

    const int position = m_src.byteToUtf16(block.taskMarkByte);
    if(position < 0 || position >= m_text.size()) {
      return {};
    }
    // The parse can be a beat behind the text. Checking the character before
    // offering the edit is what stops a stale offset from overwriting some
    // unrelated letter.
    const QChar current = m_text.at(position);
    if(current != QChar(u' ') && current.toLower() != QChar(u'x')) {
      return {};
    }

    QVariantMap edit;
    edit.insert(QStringLiteral("position"), position);
    edit.insert(QStringLiteral("from"), QString(current));
    edit.insert(QStringLiteral("to"), current == QChar(u' ') ? QStringLiteral("x") : QStringLiteral(" "));
    return edit;
  }
  return {};
}

}  // namespace heap::md
