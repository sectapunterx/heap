#include "GlobalHotkey.h"

#include <QKeyCombination>
#include <QKeySequence>
#include <QtGlobal>

namespace heap::platform {

#if defined(Q_OS_WIN)
// Defined in GlobalHotkey_win.cpp — only compiled on Windows.
std::unique_ptr<GlobalHotkey> createWindowsHotkey(QObject* parent);
#endif

namespace {

// Fallback for platforms without a native backend (Linux/macOS for now). Every
// registration fails, so AppController keeps the in-app QML shortcut as the
// only capture trigger.
class NullHotkey : public GlobalHotkey {
 public:
  using GlobalHotkey::GlobalHotkey;
  bool registerHotkey(const QString& /*seq*/) override {
    return false;
  }
  void unregister() override {
  }
};

}  // namespace

std::unique_ptr<GlobalHotkey> GlobalHotkey::create(QObject* parent) {
#if defined(Q_OS_WIN)
  return createWindowsHotkey(parent);
#else
  return std::make_unique<NullHotkey>(parent);
#endif
}

bool decodeSequence(const QString& seq, int& key, int& mods) {
  const QKeySequence ks(seq.trimmed(), QKeySequence::PortableText);
  if(ks.isEmpty()) {
    return false;
  }
  const int combined = ks[0].toCombined();
  const int k = combined & ~Qt::KeyboardModifierMask;
  if(k == 0 || k == Qt::Key_unknown) {
    return false;
  }
  key = k;
  mods = combined & Qt::KeyboardModifierMask;
  return true;
}

}  // namespace heap::platform
