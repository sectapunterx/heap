#pragma once

#include <QObject>
#include <QPointer>
#include <qqmlregistration.h>
#include <QQuickTextDocument>

class QTextDocument;

// Line height for an editable text field. QML's TextEdit/TextArea has no
// lineHeight, so a draft box set at the sheets' 1.7 (22px lines of 13px
// text) came out packed at the font's own ~15px. This sets every block of
// the field's document to a fixed line height in pixels, and keeps doing it
// as the text changes:
//
//   TextLeading { target: field.textDocument; lineHeight: Theme.px(22) }
class TextLeading : public QObject {
  Q_OBJECT
  QML_ELEMENT

  // Typed QObject* for QML: qmllint on CI (Qt 6.9) has no type for
  // QQuickTextDocument (as in SpanHighlighter).
  Q_PROPERTY(QObject* target READ targetObject WRITE setTargetObject NOTIFY targetChanged)
  Q_PROPERTY(int lineHeight READ lineHeight WRITE setLineHeight NOTIFY lineHeightChanged)

 public:
  explicit TextLeading(QObject* parent = nullptr);

  QObject* targetObject() const {
    return m_target;
  }

  void setTargetObject(QObject* t);

  int lineHeight() const {
    return m_lineHeight;
  }

  void setLineHeight(int px);

 signals:
  void targetChanged();
  void lineHeightChanged();

 private:
  void apply();

  QPointer<QQuickTextDocument> m_target;
  QPointer<QTextDocument> m_doc;
  QMetaObject::Connection m_conn;
  int m_lineHeight = 0;
  bool m_applying = false;
};
