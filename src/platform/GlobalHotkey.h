#pragma once

#include <QObject>
#include <QString>

#include <memory>

namespace heap::platform {

// System-wide (global) hotkey manager. Fires `activated(id)` even when the
// heap. window is not focused — this is what powers Quick-capture-from-anywhere.
// Several combinations can be registered at once, each under a caller-chosen
// integer `id` (e.g. one for quick-capture-task, one for quick-capture-note).
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

  // Register `seq` (QKeySequence portable text, e.g. "Ctrl+Shift+Space") under
  // `id`. Re-registering the same `id` replaces its previous combination.
  // Returns false when the platform is unsupported, the sequence is
  // unparseable, or the OS refused the combination (already owned elsewhere).
  virtual bool registerHotkey(int id, const QString& seq) = 0;
  // Release the combination bound to `id` (no-op if `id` is not registered).
  virtual void unregister(int id) = 0;
  // Release every registered combination.
  virtual void unregisterAll() = 0;

 signals:
  // Emitted with the `id` the fired combination was registered under.
  void activated(int id);

 protected:
  using QObject::QObject;
};

// Decode a QKeySequence portable string into a portable (Qt::Key, Qt::Keyboard-
// Modifiers) pair. Split out from the Windows backend so it can be unit-tested
// without pulling in <windows.h>. Returns false for an empty/keyless sequence.
//   "Ctrl+Shift+Space" → key=Qt::Key_Space, mods=Ctrl|Shift
bool decodeSequence(const QString& seq, int& key, int& mods);

}  // namespace heap::platform
