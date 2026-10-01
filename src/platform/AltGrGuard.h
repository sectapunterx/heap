#pragma once

#include <QObject>

class QKeyEvent;

// Windows reports AltGr as Ctrl+Alt, so a Ctrl+Alt+<letter> shortcut ate the
// character it makes on that layout: € on German, ę/ł/ń on Polish. Typing in
// the search box, a note or a dialog field opened the event editor instead
// (SHELL-2, audit 2026-09-30).
//
// Installed on the application: while an editable text item has focus, a
// Ctrl+Alt key that carries printable text is the field's, not a shortcut's.
// Ctrl+Alt+E outside a text field still fires.
namespace heap::platform {

class AltGrGuard : public QObject {
  Q_OBJECT
 public:
  using QObject::QObject;

  // The rule, without the event plumbing: Ctrl and Alt both held, and the
  // key produced text that is all printable.
  static bool isAltGrText(const QKeyEvent& event);
  // An item that takes typed text: a TextInput/TextEdit (and the controls
  // built on them) that is not read-only.
  static bool isEditableText(const QObject* item);

 protected:
  bool eventFilter(QObject* watched, QEvent* event) override;
};

}  // namespace heap::platform
