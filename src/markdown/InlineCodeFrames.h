#pragma once

#include <QObject>
#include <QPointer>
#include <qqmlregistration.h>
#include <QQuickTextDocument>
#include <QTimer>
#include <QVariantList>

// Where the inline code of a rich-text TextEdit sits, as rectangles in the
// text's own coordinates (R2-020: `Retry-After` in a hairline pill). Qt's
// rich text cannot stroke an inline span, so the view draws the pill under
// the text from these. A span is the text set in `family` (the bundled mono,
// which only inline code uses in a paragraph); a span that wraps gives one
// rectangle per line.
class InlineCodeFrames : public QObject {
  Q_OBJECT
  QML_ELEMENT
  Q_PROPERTY(QQuickTextDocument* target READ target WRITE setTarget NOTIFY targetChanged)
  Q_PROPERTY(QString family READ family WRITE setFamily NOTIFY familyChanged)
  Q_PROPERTY(QVariantList rects READ rects NOTIFY rectsChanged)

 public:
  explicit InlineCodeFrames(QObject* parent = nullptr);

  QQuickTextDocument* target() const {
    return m_target;
  }

  void setTarget(QQuickTextDocument* target);

  QString family() const {
    return m_family;
  }

  void setFamily(const QString& family);

  QVariantList rects() const {
    return m_rects;
  }

  // Measure again now (the text's width changed).
  Q_INVOKABLE void refresh();

 signals:
  void targetChanged();
  void familyChanged();
  void rectsChanged();

 private:
  void schedule();

  QPointer<QQuickTextDocument> m_target;
  QString m_family;
  QVariantList m_rects;
  QTimer m_timer;
};
