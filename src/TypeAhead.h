#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class QKeyEvent;

// Type to search (APP-117): on the board, a letter typed while no text field
// has focus starts a search with it, the way Dota's hero grid filters as soon
// as you type — no Ctrl+F first.
//
// Installed on the application while it exists. It only ever sees keys the
// shortcut map left alone: the board's own bare letters (J/K/H/L, M, E, Z, O)
// are taken by their shortcuts before a key press is delivered, so they keep
// working; every other printable key reaches here and is handed to typed().
// Once the search field has focus it types into the field like any other
// text, J and K included.
class TypeAhead : public QObject {
  Q_OBJECT
  QML_ELEMENT
  Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

 public:
  explicit TypeAhead(QObject* parent = nullptr);
  ~TypeAhead() override;

  bool enabled() const {
    return m_enabled;
  }

  void setEnabled(bool on);

  // The rule, without the event plumbing: the text `event` types when it
  // should start a search, else empty. Only plain or Shifted keys that type
  // one printable, non-blank character, and only while `focus` is not a field
  // that takes text.
  static QString startingText(const QKeyEvent& event, const QObject* focus);

 signals:
  void enabledChanged();
  void typed(const QString& text);

 protected:
  bool eventFilter(QObject* watched, QEvent* event) override;

 private:
  bool m_enabled = false;
};
