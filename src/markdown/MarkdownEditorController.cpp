#include "markdown/MarkdownEditorController.h"

#include <QTextDocument>

namespace heap::md {

MarkdownEditorController::MarkdownEditorController(QObject* parent) : QObject(parent) {
}

void MarkdownEditorController::setTarget(QQuickTextDocument* target) {
  if(m_target == target) {
    return;
  }
  m_target = target;
  emit targetChanged();
}

QTextDocument* MarkdownEditorController::document() const {
  return m_target != nullptr ? m_target->textDocument() : nullptr;
}

void MarkdownEditorController::setCursorPosition(int position) {
  if(m_selection.end == position && m_selection.start == position) {
    return;
  }
  m_selection = Selection::at(position);
  emit selectionChanged();
}

void MarkdownEditorController::setSelectionStart(int position) {
  if(m_selection.start == position) {
    return;
  }
  m_selection.start = position;
  emit selectionChanged();
}

void MarkdownEditorController::setSelectionEnd(int position) {
  if(m_selection.end == position) {
    return;
  }
  m_selection.end = position;
  emit selectionChanged();
}

void MarkdownEditorController::apply(const Selection& result) {
  m_selection = result;
  emit selectionChanged();
  // Only the editor can move its own cursor, so the new selection is asked
  // for rather than set.
  emit selectionRequested(result.start, result.end);
}

void MarkdownEditorController::toggleBold() {
  apply(toggleInlineStyle(document(), m_selection, InlineStyle::Bold));
}

void MarkdownEditorController::toggleItalic() {
  apply(toggleInlineStyle(document(), m_selection, InlineStyle::Italic));
}

void MarkdownEditorController::toggleStrikethrough() {
  apply(toggleInlineStyle(document(), m_selection, InlineStyle::Strikethrough));
}

void MarkdownEditorController::toggleCode() {
  apply(toggleInlineStyle(document(), m_selection, InlineStyle::Code));
}

void MarkdownEditorController::toggleHighlight() {
  apply(toggleInlineStyle(document(), m_selection, InlineStyle::Highlight));
}

void MarkdownEditorController::insertLink(const QString& url) {
  apply(heap::md::insertLink(document(), m_selection, url));
}

void MarkdownEditorController::cycleHeading() {
  apply(heap::md::cycleHeading(document(), m_selection));
}

void MarkdownEditorController::toggleTask() {
  apply(toggleTaskAtCaret(document(), m_selection));
}

void MarkdownEditorController::indent() {
  apply(indentLines(document(), m_selection, false));
}

void MarkdownEditorController::outdent() {
  apply(indentLines(document(), m_selection, true));
}

void MarkdownEditorController::paste(const QString& text) {
  apply(pasteText(document(), m_selection, text));
}

bool MarkdownEditorController::handleReturn() {
  bool handled = false;
  const Selection result = continueLine(document(), m_selection, &handled);
  if(handled) {
    apply(result);
  }
  return handled;
}

bool MarkdownEditorController::insideFence() const {
  return isInsideFence(document(), m_selection.caret());
}

}  // namespace heap::md
