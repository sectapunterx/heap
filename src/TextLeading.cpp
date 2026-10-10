#include "TextLeading.h"

#include <QTextBlock>
#include <QTextBlockFormat>
#include <QTextCursor>
#include <QTextDocument>

TextLeading::TextLeading(QObject* parent) : QObject(parent) {
}

void TextLeading::setTargetObject(QObject* t) {
  auto* target = qobject_cast<QQuickTextDocument*>(t);
  if(target == m_target) {
    return;
  }
  QObject::disconnect(m_conn);
  m_target = target;
  m_doc = target != nullptr ? target->textDocument() : nullptr;
  if(m_doc != nullptr) {
    m_conn = connect(m_doc, &QTextDocument::contentsChanged, this, &TextLeading::apply);
  }
  emit targetChanged();
  apply();
}

void TextLeading::setLineHeight(int px) {
  if(px == m_lineHeight) {
    return;
  }
  m_lineHeight = px;
  emit lineHeightChanged();
  apply();
}

void TextLeading::apply() {
  if(m_applying || m_doc == nullptr || m_lineHeight <= 0) {
    return;
  }
  m_applying = true;
  // Text set from code (setPlainText) leaves no undo history; the format
  // must not become the first thing Ctrl Z takes back.
  const bool fresh = !m_doc->isUndoAvailable();
  bool changed = false;
  QTextCursor cursor(m_doc);
  for(QTextBlock b = m_doc->begin(); b.isValid(); b = b.next()) {
    const QTextBlockFormat cur = b.blockFormat();
    if(cur.lineHeightType() == QTextBlockFormat::FixedHeight && qRound(cur.lineHeight()) == m_lineHeight) {
      continue;
    }
    if(!changed) {
      cursor.joinPreviousEditBlock();
      changed = true;
    }
    QTextBlockFormat f;
    f.setLineHeight(m_lineHeight, QTextBlockFormat::FixedHeight);
    cursor.setPosition(b.position());
    cursor.mergeBlockFormat(f);
  }
  if(changed) {
    cursor.endEditBlock();
    if(fresh) {
      m_doc->clearUndoRedoStacks();
    }
  }
  m_applying = false;
}
