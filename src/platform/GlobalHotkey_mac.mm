#include "GlobalHotkey.h"

#include <QHash>
#include <QtGlobal>

#import <Carbon/Carbon.h>

// macOS global-hotkey backend (HEAP-68). Mirrors GlobalHotkey_win.cpp but uses
// the Carbon RegisterEventHotKey API (still the supported way to install a
// system-wide hotkey without accessibility permissions). A single application
// event handler dispatches kEventHotKeyPressed back to the owning instance.

namespace heap::platform {

namespace {

// Base for per-process hotkey ids; the caller id is added so several
// combinations coexist. Signature tags the ids as ours.
constexpr UInt32 kHotkeyIdBase = 0xB33F;
constexpr OSType kHotkeySignature = 'heap';

UInt32 toMacMods(int qtMods) {
  UInt32 m = 0;
  if(qtMods & Qt::ControlModifier) {
    m |= controlKey;
  }
  if(qtMods & Qt::ShiftModifier) {
    m |= shiftKey;
  }
  if(qtMods & Qt::AltModifier) {
    m |= optionKey;
  }
  if(qtMods & Qt::MetaModifier) {
    m |= cmdKey;
  }
  return m;
}

// Qt::Key → macOS (Carbon) virtual keycode. The ANSI keycodes are not
// contiguous, so map explicitly. Returns UINT32_MAX for anything unmapped so
// registration fails cleanly rather than binding the wrong key.
UInt32 toMacVk(int qtKey) {
  switch(qtKey) {
    case Qt::Key_A: return kVK_ANSI_A;
    case Qt::Key_B: return kVK_ANSI_B;
    case Qt::Key_C: return kVK_ANSI_C;
    case Qt::Key_D: return kVK_ANSI_D;
    case Qt::Key_E: return kVK_ANSI_E;
    case Qt::Key_F: return kVK_ANSI_F;
    case Qt::Key_G: return kVK_ANSI_G;
    case Qt::Key_H: return kVK_ANSI_H;
    case Qt::Key_I: return kVK_ANSI_I;
    case Qt::Key_J: return kVK_ANSI_J;
    case Qt::Key_K: return kVK_ANSI_K;
    case Qt::Key_L: return kVK_ANSI_L;
    case Qt::Key_M: return kVK_ANSI_M;
    case Qt::Key_N: return kVK_ANSI_N;
    case Qt::Key_O: return kVK_ANSI_O;
    case Qt::Key_P: return kVK_ANSI_P;
    case Qt::Key_Q: return kVK_ANSI_Q;
    case Qt::Key_R: return kVK_ANSI_R;
    case Qt::Key_S: return kVK_ANSI_S;
    case Qt::Key_T: return kVK_ANSI_T;
    case Qt::Key_U: return kVK_ANSI_U;
    case Qt::Key_V: return kVK_ANSI_V;
    case Qt::Key_W: return kVK_ANSI_W;
    case Qt::Key_X: return kVK_ANSI_X;
    case Qt::Key_Y: return kVK_ANSI_Y;
    case Qt::Key_Z: return kVK_ANSI_Z;
    case Qt::Key_0: return kVK_ANSI_0;
    case Qt::Key_1: return kVK_ANSI_1;
    case Qt::Key_2: return kVK_ANSI_2;
    case Qt::Key_3: return kVK_ANSI_3;
    case Qt::Key_4: return kVK_ANSI_4;
    case Qt::Key_5: return kVK_ANSI_5;
    case Qt::Key_6: return kVK_ANSI_6;
    case Qt::Key_7: return kVK_ANSI_7;
    case Qt::Key_8: return kVK_ANSI_8;
    case Qt::Key_9: return kVK_ANSI_9;
    case Qt::Key_F1: return kVK_F1;
    case Qt::Key_F2: return kVK_F2;
    case Qt::Key_F3: return kVK_F3;
    case Qt::Key_F4: return kVK_F4;
    case Qt::Key_F5: return kVK_F5;
    case Qt::Key_F6: return kVK_F6;
    case Qt::Key_F7: return kVK_F7;
    case Qt::Key_F8: return kVK_F8;
    case Qt::Key_F9: return kVK_F9;
    case Qt::Key_F10: return kVK_F10;
    case Qt::Key_F11: return kVK_F11;
    case Qt::Key_F12: return kVK_F12;
    case Qt::Key_Space: return kVK_Space;
    case Qt::Key_Return:
    case Qt::Key_Enter: return kVK_Return;
    case Qt::Key_Tab: return kVK_Tab;
    case Qt::Key_Backslash: return kVK_ANSI_Backslash;
    case Qt::Key_Period: return kVK_ANSI_Period;
    case Qt::Key_Comma: return kVK_ANSI_Comma;
    case Qt::Key_Slash: return kVK_ANSI_Slash;
    default: return UINT32_MAX;
  }
}

class MacHotkey : public GlobalHotkey {
 public:
  explicit MacHotkey(QObject* parent) : GlobalHotkey(parent) {
    EventTypeSpec spec{kEventClassKeyboard, kEventHotKeyPressed};
    InstallEventHandler(GetApplicationEventTarget(), &MacHotkey::handler, 1, &spec, this, &m_handlerRef);
  }

  ~MacHotkey() override {
    unregisterAll();
    if(m_handlerRef != nullptr) {
      RemoveEventHandler(m_handlerRef);
    }
  }

  bool registerHotkey(int id, const QString& seq) override {
    unregister(id);
    int key = 0;
    int mods = 0;
    if(!decodeSequence(seq, key, mods)) {
      return false;
    }
    const UInt32 vk = toMacVk(key);
    if(vk == UINT32_MAX) {
      return false;
    }
    const EventHotKeyID hkid{kHotkeySignature, static_cast<UInt32>(kHotkeyIdBase + id)};
    EventHotKeyRef ref = nullptr;
    if(RegisterEventHotKey(vk, toMacMods(mods), hkid, GetApplicationEventTarget(), 0, &ref) != noErr || ref == nullptr) {
      return false;
    }
    m_refs.insert(id, ref);
    return true;
  }

  void unregister(int id) override {
    auto it = m_refs.find(id);
    if(it != m_refs.end()) {
      UnregisterEventHotKey(it.value());
      m_refs.erase(it);
    }
  }

  void unregisterAll() override {
    for(auto it = m_refs.cbegin(); it != m_refs.cend(); ++it) {
      UnregisterEventHotKey(it.value());
    }
    m_refs.clear();
  }

  // Emit from a member so the static C handler can raise the base signal.
  void fire(int id) {
    emit activated(id);
  }

 private:
  static OSStatus handler(EventHandlerCallRef /*next*/, EventRef event, void* userData) {
    EventHotKeyID hkid{};
    if(GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, nullptr, sizeof(hkid), nullptr, &hkid) == noErr) {
      auto* self = static_cast<MacHotkey*>(userData);
      const int id = static_cast<int>(hkid.id) - static_cast<int>(kHotkeyIdBase);
      if(self != nullptr && self->m_refs.contains(id)) {
        self->fire(id);
      }
    }
    return noErr;
  }

  QHash<int, EventHotKeyRef> m_refs;
  EventHandlerRef m_handlerRef = nullptr;
};

}  // namespace

std::unique_ptr<GlobalHotkey> createMacHotkey(QObject* parent) {
  return std::make_unique<MacHotkey>(parent);
}

}  // namespace heap::platform
