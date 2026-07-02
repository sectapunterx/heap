#pragma once

#include <QObject>
#include <QString>

#include <memory>

namespace heap::platform {

// System-wide (global) hotkey. Fires `activated()` even when the heap. window
// is not focused — this is what powers Quick-capture-from-anywhere.
//
// Backends:
//   Windows → RegisterHotKey + a QAbstractNativeEventFilter that watches for
//             WM_HOTKEY on the GUI thread.
//   Others  → create() returns a no-op instance whose registerHotkey() always
//             returns false, so callers transparently fall back to the in-app
//             QML Shortcut (which only works while the window is focused).
class GlobalHotkey : public QObject {
  Q_OBJECT
 public:
  static std::unique_ptr<GlobalHotkey> create(QObject* parent = nullptr);
  ~GlobalHotkey() override = default;

  // Register `seq` given as QKeySequence portable text ("Ctrl+Shift+Space").
  // Replaces any previously registered combination. Returns false when the
  // platform is unsupported, the sequence is unparseable, or the OS refused
  // the combination (already owned by another application).
  virtual bool registerHotkey(const QString& seq) = 0;
  virtual void unregister() = 0;

 signals:
  void activated();

 protected:
  using QObject::QObject;
};

// Decode a QKeySequence portable string into a portable (Qt::Key, Qt::Keyboard-
// Modifiers) pair. Split out from the Windows backend so it can be unit-tested
// without pulling in <windows.h>. Returns false for an empty/keyless sequence.
//   "Ctrl+Shift+Space" → key=Qt::Key_Space, mods=Ctrl|Shift
bool decodeSequence(const QString& seq, int& key, int& mods);

}  // namespace heap::platform
