#pragma once

#include <QColor>
#include <qqmlregistration.h>
#include <QQuickTextDocument>
#include <QSyntaxHighlighter>
#include <QVariantList>
#include <QVariantMap>

// Colours the parts of the task input that were recognised (APP-266): the
// date, the deadline, the estimate, the priority, a label. The spans are
// offsets into the whole text ({start, end, kind}); `colors` maps a kind to
// its colour. Anything else keeps the field's own colour.
class SpanHighlighter : public QSyntaxHighlighter {
  Q_OBJECT
  QML_ELEMENT

  Q_PROPERTY(QQuickTextDocument* target READ target WRITE setTarget NOTIFY targetChanged)
  Q_PROPERTY(QVariantList spans READ spans WRITE setSpans NOTIFY spansChanged)
  Q_PROPERTY(QVariantMap colors READ colors WRITE setColors NOTIFY colorsChanged)

 public:
  explicit SpanHighlighter(QObject* parent = nullptr);

  QQuickTextDocument* target() const {
    return m_target;
  }

  void setTarget(QQuickTextDocument* t);

  QVariantList spans() const {
    return m_spans;
  }

  void setSpans(const QVariantList& s);

  QVariantMap colors() const {
    return m_colors;
  }

  void setColors(const QVariantMap& c);

 signals:
  void targetChanged();
  void spansChanged();
  void colorsChanged();

 protected:
  void highlightBlock(const QString& text) override;

 private:
  QQuickTextDocument* m_target = nullptr;
  QVariantList m_spans;
  QVariantMap m_colors;
};
