#include "markdown/InlineCodeFrames.h"

#include <QAbstractTextDocumentLayout>
#include <QRectF>
#include <QTextBlock>
#include <QTextDocument>
#include <QTextLayout>

InlineCodeFrames::InlineCodeFrames(QObject* parent) : QObject(parent) {
  m_timer.setSingleShot(true);
  m_timer.setInterval(0);
  connect(&m_timer, &QTimer::timeout, this, &InlineCodeFrames::refresh);
}

void InlineCodeFrames::setTarget(QQuickTextDocument* target) {
  if(m_target == target) {
    return;
  }
  if(m_target && m_target->textDocument()) {
    disconnect(m_target->textDocument(), nullptr, this, nullptr);
    if(auto* layout = m_target->textDocument()->documentLayout()) {
      disconnect(layout, nullptr, this, nullptr);
    }
  }
  m_target = target;
  if(m_target && m_target->textDocument()) {
    QTextDocument* doc = m_target->textDocument();
    connect(doc, &QTextDocument::contentsChanged, this, &InlineCodeFrames::schedule);
    if(auto* layout = doc->documentLayout()) {
      connect(layout, &QAbstractTextDocumentLayout::documentSizeChanged, this, &InlineCodeFrames::schedule);
      connect(layout, &QAbstractTextDocumentLayout::update, this, &InlineCodeFrames::schedule);
    }
  }
  emit targetChanged();
  schedule();
}

void InlineCodeFrames::setFamily(const QString& family) {
  if(m_family == family) {
    return;
  }
  m_family = family;
  emit familyChanged();
  schedule();
}

void InlineCodeFrames::schedule() {
  m_timer.start();
}

void InlineCodeFrames::refresh() {
  QVariantList out;
  QTextDocument* doc = m_target ? m_target->textDocument() : nullptr;
  if(doc && !m_family.isEmpty()) {
    for(QTextBlock block = doc->begin(); block.isValid(); block = block.next()) {
      const QTextLayout* layout = block.layout();
      if(!layout || layout->lineCount() == 0) {
        continue;
      }
      const QPointF origin = layout->position();
      for(auto it = block.begin(); !it.atEnd(); ++it) {
        const QTextFragment frag = it.fragment();
        if(!frag.isValid() || !frag.charFormat().fontFamilies().toStringList().contains(m_family)) {
          continue;
        }
        const int start = frag.position() - block.position();
        const int end = start + frag.length();
        for(int i = 0; i < layout->lineCount(); ++i) {
          const QTextLine line = layout->lineAt(i);
          const int s = qMax(start, line.textStart());
          const int e = qMin(end, line.textStart() + line.textLength());
          if(s >= e) {
            continue;
          }
          const qreal x1 = line.cursorToX(s);
          const qreal x2 = line.cursorToX(e);
          out.append(QRectF(origin.x() + qMin(x1, x2), origin.y() + line.y(), qAbs(x2 - x1), line.height()));
        }
      }
    }
  }
  if(out != m_rects) {
    m_rects = out;
    emit rectsChanged();
  }
}
