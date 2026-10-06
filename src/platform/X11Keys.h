#pragma once

#include <QList>
#include <QString>

#include <cstdint>
#include <vector>

// The pure half of the Linux global hotkey (APP-171): Qt key + modifiers to
// what X11 grabs (a keysym and a modifier mask) and to what the XDG desktop
// portal asks for ("CTRL+SHIFT+space"). No X11 or D-Bus headers here, so it
// builds and is tested on every platform.
namespace heap::platform::x11 {

// <X11/X.h> modifier masks, spelled out so this compiles without X11.
inline constexpr std::uint16_t kShiftMask = 1U << 0U;
inline constexpr std::uint16_t kLockMask = 1U << 1U;  // Caps Lock
inline constexpr std::uint16_t kControlMask = 1U << 2U;
inline constexpr std::uint16_t kMod1Mask = 1U << 3U;  // Alt
inline constexpr std::uint16_t kMod2Mask = 1U << 4U;  // Num Lock
inline constexpr std::uint16_t kMod4Mask = 1U << 6U;  // Super / Windows

struct KeyGrab {
  std::uint32_t keysym = 0;
  std::uint16_t mods = 0;  // kShiftMask | kControlMask | kMod1Mask | kMod4Mask
};

// Qt::Key + Qt::KeyboardModifiers to an X11 grab. False for a key a capture
// hotkey has no business using (or that has no keysym here), so registration
// fails cleanly instead of grabbing the wrong key.
bool toKeyGrab(int qt_key, int qt_mods, KeyGrab& out);

// Every modifier state the grab has to cover: X11 matches the state exactly,
// so with Num Lock or Caps Lock on a plain grab never fires.
QList<std::uint16_t> lockVariants(std::uint16_t mods);

// The modifiers of a key event that a grab is about (locks dropped).
std::uint16_t significantMods(std::uint16_t state);

// The keycode that produces `keysym` in a keyboard mapping as
// GetKeyboardMapping returns it: `per_keycode` keysyms for each keycode from
// `min_keycode` on. 0 when no key on this keyboard produces it.
std::uint8_t keycodeFor(const std::vector<std::uint32_t>& table, int per_keycode, int min_keycode, std::uint32_t keysym);

// The binding in the XDG shortcuts notation the GlobalShortcuts portal takes
// as `preferred_trigger`: "CTRL+SHIFT+space". Empty for an unmapped key.
QString portalTrigger(int qt_key, int qt_mods);

}  // namespace heap::platform::x11
