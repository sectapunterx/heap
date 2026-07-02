#include "GlobalHotkey.h"

#include <QAbstractNativeEventFilter>
#include <QByteArray>
#include <QCoreApplication>

// <windows.h> must come after the Qt includes so its min/max macros don't
// clobber Qt headers.
#include <windows.h>

namespace heap::platform {

namespace {

// Arbitrary per-process hotkey id. RegisterHotKey with a null window handle
// posts WM_HOTKEY as a thread message identified by this id.
constexpr int kHotkeyId = 0xB33F;

UINT toWinMods(int qtMods) {
  UINT m = 0;
  if(qtMods & Qt::ControlModifier) {
    m |= MOD_CONTROL;
  }
  if(qtMods & Qt::ShiftModifier) {
    m |= MOD_SHIFT;
  }
  if(qtMods & Qt::AltModifier) {
    m |= MOD_ALT;
  }
  if(qtMods & Qt::MetaModifier) {
    m |= MOD_WIN;
  }
  // Don't auto-repeat while the keys are held — one press, one capture window.
  m |= MOD_NOREPEAT;
  return m;
}

// Map a Qt::Key to a Win32 virtual-key code. Covers the keys that make sense as
// a capture hotkey; returns 0 for anything unmapped so registration fails
// cleanly rather than binding the wrong key.
UINT toVk(int qtKey) {
  if(qtKey >= Qt::Key_A && qtKey <= Qt::Key_Z) {
    return static_cast<UINT>('A' + (qtKey - Qt::Key_A));
  }
  if(qtKey >= Qt::Key_0 && qtKey <= Qt::Key_9) {
    return static_cast<UINT>('0' + (qtKey - Qt::Key_0));
  }
  if(qtKey >= Qt::Key_F1 && qtKey <= Qt::Key_F24) {
    return static_cast<UINT>(VK_F1 + (qtKey - Qt::Key_F1));
  }
  switch(qtKey) {
    case Qt::Key_Space:
      return VK_SPACE;
    case Qt::Key_Return:
    case Qt::Key_Enter:
      return VK_RETURN;
    case Qt::Key_Tab:
      return VK_TAB;
    case Qt::Key_Backslash:
      return VK_OEM_5;
    case Qt::Key_Period:
      return VK_OEM_PERIOD;
    case Qt::Key_Comma:
      return VK_OEM_COMMA;
    case Qt::Key_Slash:
      return VK_OEM_2;
    default:
      return 0;
  }
}

class WinHotkey : public GlobalHotkey, public QAbstractNativeEventFilter {
 public:
  explicit WinHotkey(QObject* parent) : GlobalHotkey(parent) {
    if(auto* app = QCoreApplication::instance()) {
      app->installNativeEventFilter(this);
    }
  }

  ~WinHotkey() override {
    unregister();
    if(auto* app = QCoreApplication::instance()) {
      app->removeNativeEventFilter(this);
    }
  }

  bool registerHotkey(const QString& seq) override {
    unregister();
    int key = 0;
    int mods = 0;
    if(!decodeSequence(seq, key, mods)) {
      return false;
    }
    const UINT vk = toVk(key);
    if(vk == 0) {
      return false;
    }
    if(!::RegisterHotKey(nullptr, kHotkeyId, toWinMods(mods), vk)) {
      return false;
    }
    m_registered = true;
    return true;
  }

  void unregister() override {
    if(m_registered) {
      ::UnregisterHotKey(nullptr, kHotkeyId);
      m_registered = false;
    }
  }

  bool nativeEventFilter(const QByteArray& eventType, void* message, qintptr* /*result*/) override {
    if(eventType != "windows_generic_MSG") {
      return false;
    }
    auto* msg = static_cast<MSG*>(message);
    if(msg != nullptr && msg->message == WM_HOTKEY && static_cast<int>(msg->wParam) == kHotkeyId) {
      emit activated();
      return true;
    }
    return false;
  }

 private:
  bool m_registered = false;
};

}  // namespace

std::unique_ptr<GlobalHotkey> createWindowsHotkey(QObject* parent) {
  return std::make_unique<WinHotkey>(parent);
}

}  // namespace heap::platform
