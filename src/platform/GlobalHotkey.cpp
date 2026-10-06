#include "GlobalHotkey.h"

#include <QKeyCombination>
#include <QKeySequence>
#include <QtGlobal>

namespace heap::platform {

#if defined(Q_OS_WIN)
// Defined in GlobalHotkey_win.cpp — only compiled on Windows.
std::unique_ptr<GlobalHotkey> createWindowsHotkey(QObject* parent);
#elif defined(Q_OS_MAC)
// Defined in GlobalHotkey_mac.mm — only compiled on macOS.
std::unique_ptr<GlobalHotkey> createMacHotkey(QObject* parent);
#elif defined(Q_OS_LINUX)
// Defined in GlobalHotkey_linux.cpp: X11 or the Wayland portal, or null when
// the session has neither.
std::unique_ptr<GlobalHotkey> createLinuxHotkey(QObject* parent);
#endif

namespace {

// Fallback for platforms or sessions without a backend. Every
// registration fails, so AppController keeps the in-app QML shortcut as the
// only capture trigger.
class NullHotkey : public GlobalHotkey {
 public:
  using GlobalHotkey::GlobalHotkey;

  bool registerHotkey(int /*id*/, const QString& /*seq*/) override {
    return false;
  }

  void unregister(int /*id*/) override {
  }

  void unregisterAll() override {
  }

  QString backend() const override {
    return QStringLiteral("none");
  }
};

}  // namespace

std::unique_ptr<GlobalHotkey> GlobalHotkey::create(QObject* parent) {
#if defined(Q_OS_WIN)
  return createWindowsHotkey(parent);
#elif defined(Q_OS_MAC)
  return createMacHotkey(parent);
#elif defined(Q_OS_LINUX)
  if(auto native = createLinuxHotkey(parent)) {
    return native;
  }
  return std::make_unique<NullHotkey>(parent);
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
