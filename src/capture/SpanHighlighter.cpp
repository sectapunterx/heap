#include "capture/SpanHighlighter.h"

#include <QTextCharFormat>
#include <QTextDocument>

#include <algorithm>

SpanHighlighter::SpanHighlighter(QObject* parent) : QSyntaxHighlighter(parent) {
}

void SpanHighlighter::setTarget(QQuickTextDocument* t) {
  if(t == m_target) {
    return;
  }
  m_target = t;
  setDocument(t != nullptr ? t->textDocument() : nullptr);
  emit targetChanged();
}

void SpanHighlighter::setSpans(const QVariantList& s) {
  if(s == m_spans) {
    return;
  }
  m_spans = s;
  emit spansChanged();
  rehighlight();
}

void SpanHighlighter::setColors(const QVariantMap& c) {
  if(c == m_colors) {
    return;
  }
  m_colors = c;
  emit colorsChanged();
  rehighlight();
}

void SpanHighlighter::highlightBlock(const QString& text) {
  const int blockStart = currentBlock().position();
  const int blockEnd = blockStart + static_cast<int>(text.size());
  for(const QVariant& v : m_spans) {
    const QVariantMap m = v.toMap();
    const int start = std::max(m.value(QStringLiteral("start")).toInt(), blockStart);
    const int end = std::min(m.value(QStringLiteral("end")).toInt(), blockEnd);
    const QVariant colour = m_colors.value(m.value(QStringLiteral("kind")).toString());
    if(end <= start || !colour.isValid()) {
      continue;
    }
    QTextCharFormat f;
    f.setForeground(colour.value<QColor>());
    setFormat(start - blockStart, end - start, f);
  }
}
