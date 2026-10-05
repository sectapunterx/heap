#include "platform/GlobalHotkey.h"
#include "platform/X11Keys.h"

#include <QKeySequence>

#include <gtest/gtest.h>

#include <memory>

using heap::platform::decodeSequence;

// ─── decodeSequence: portable QKeySequence → (Qt::Key, modifiers) ───
// This is the parsing layer the Windows RegisterHotKey backend feeds off; it is
// pure and header-only w.r.t. the OS, so it can be exercised on any runner.

TEST(DecodeSequence, CtrlShiftSpace) {
  int key = 0;
  int mods = 0;
  ASSERT_TRUE(decodeSequence(QStringLiteral("Ctrl+Shift+Space"), key, mods));
  EXPECT_EQ(key, static_cast<int>(Qt::Key_Space));
  EXPECT_TRUE(mods & Qt::ControlModifier);
  EXPECT_TRUE(mods & Qt::ShiftModifier);
  EXPECT_FALSE(mods & Qt::AltModifier);
}

TEST(DecodeSequence, CtrlShiftLetter) {
  int key = 0;
  int mods = 0;
  ASSERT_TRUE(decodeSequence(QStringLiteral("Ctrl+Shift+N"), key, mods));
  EXPECT_EQ(key, static_cast<int>(Qt::Key_N));
  EXPECT_EQ(mods, static_cast<int>(Qt::ControlModifier | Qt::ShiftModifier));
}

TEST(DecodeSequence, FunctionKeyNoMods) {
  int key = 0;
  int mods = 0;
  ASSERT_TRUE(decodeSequence(QStringLiteral("F5"), key, mods));
  EXPECT_EQ(key, static_cast<int>(Qt::Key_F5));
  EXPECT_EQ(mods, static_cast<int>(Qt::NoModifier));
}

TEST(DecodeSequence, AltMeta) {
  int key = 0;
  int mods = 0;
  ASSERT_TRUE(decodeSequence(QStringLiteral("Alt+Meta+K"), key, mods));
  EXPECT_EQ(key, static_cast<int>(Qt::Key_K));
  EXPECT_TRUE(mods & Qt::AltModifier);
  EXPECT_TRUE(mods & Qt::MetaModifier);
}

TEST(DecodeSequence, WhitespaceTolerated) {
  int key = 0;
  int mods = 0;
  ASSERT_TRUE(decodeSequence(QStringLiteral("  Ctrl+Shift+Space  "), key, mods));
  EXPECT_EQ(key, static_cast<int>(Qt::Key_Space));
}

TEST(DecodeSequence, EmptyRejected) {
  int key = 0;
  int mods = 0;
  EXPECT_FALSE(decodeSequence(QString(), key, mods));
  EXPECT_FALSE(decodeSequence(QStringLiteral("   "), key, mods));
}

TEST(DecodeSequence, ModifierOnlyRejected) {
  // A bare modifier has no base key to bind — must be rejected so the backend
  // never calls RegisterHotKey with vk == 0.
  int key = 0;
  int mods = 0;
  EXPECT_FALSE(decodeSequence(QStringLiteral("Ctrl"), key, mods));
}

// The backend names itself, so Settings can tell a session where heap cannot
// listen system-wide (APP-171). A test has no X11 or Wayland session.
TEST(GlobalHotkeyBackend, NamesItself) {
  const std::unique_ptr<heap::platform::GlobalHotkey> hotkey = heap::platform::GlobalHotkey::create();
  ASSERT_NE(hotkey, nullptr);
#ifdef Q_OS_WIN
  EXPECT_EQ(hotkey->backend(), QStringLiteral("native"));
#elif defined(Q_OS_LINUX)
  EXPECT_EQ(hotkey->backend(), QStringLiteral("none"));
  EXPECT_FALSE(hotkey->registerHotkey(1, QStringLiteral("Ctrl+Shift+Space")));
#endif
}

// ─── Linux (APP-171): Qt key + modifiers → X11 grab / portal trigger ───
// Pure, so it runs on every platform; the xcb and portal backends only feed
// these into the X server and D-Bus.

namespace x11 = heap::platform::x11;

TEST(X11Keys, CtrlShiftSpaceGrab) {
  x11::KeyGrab g;
  ASSERT_TRUE(x11::toKeyGrab(Qt::Key_Space, Qt::ControlModifier | Qt::ShiftModifier, g));
  EXPECT_EQ(g.keysym, 0x0020U);
  EXPECT_EQ(g.mods, x11::kControlMask | x11::kShiftMask);
}

TEST(X11Keys, LettersAreLowercaseKeysyms) {
  x11::KeyGrab g;
  ASSERT_TRUE(x11::toKeyGrab(Qt::Key_N, Qt::ControlModifier | Qt::AltModifier, g));
  EXPECT_EQ(g.keysym, 0x006eU);  // XK_n
  EXPECT_EQ(g.mods, x11::kControlMask | x11::kMod1Mask);
}

TEST(X11Keys, FunctionDigitAndSuper) {
  x11::KeyGrab g;
  ASSERT_TRUE(x11::toKeyGrab(Qt::Key_F12, Qt::MetaModifier, g));
  EXPECT_EQ(g.keysym, 0xffc9U);  // XK_F12
  EXPECT_EQ(g.mods, x11::kMod4Mask);
  ASSERT_TRUE(x11::toKeyGrab(Qt::Key_7, Qt::NoModifier, g));
  EXPECT_EQ(g.keysym, 0x0037U);
  EXPECT_EQ(g.mods, 0);
}

TEST(X11Keys, UnmappedKeyIsRefused) {
  x11::KeyGrab g;
  EXPECT_FALSE(x11::toKeyGrab(Qt::Key_VolumeUp, Qt::ControlModifier, g));
  EXPECT_FALSE(x11::toKeyGrab(0, Qt::ControlModifier, g));
}

TEST(X11Keys, FromAPortableSequence) {
  int key = 0;
  int mods = 0;
  ASSERT_TRUE(decodeSequence(QStringLiteral("Ctrl+Shift+N"), key, mods));
  x11::KeyGrab g;
  ASSERT_TRUE(x11::toKeyGrab(key, mods, g));
  EXPECT_EQ(g.keysym, 0x006eU);
  EXPECT_EQ(g.mods, x11::kControlMask | x11::kShiftMask);
}

TEST(X11Keys, GrabCoversNumLockAndCapsLock) {
  const QList<std::uint16_t> v = x11::lockVariants(x11::kControlMask);
  ASSERT_EQ(v.size(), 4);
  EXPECT_TRUE(v.contains(x11::kControlMask));
  EXPECT_TRUE(v.contains(x11::kControlMask | x11::kLockMask));
  EXPECT_TRUE(v.contains(x11::kControlMask | x11::kMod2Mask));
  EXPECT_TRUE(v.contains(x11::kControlMask | x11::kLockMask | x11::kMod2Mask));
  // A key event with Num Lock on still matches the grab.
  EXPECT_EQ(x11::significantMods(x11::kControlMask | x11::kMod2Mask | x11::kLockMask), x11::kControlMask);
}

TEST(X11Keys, KeycodeFromAKeyboardMapping) {
  // Two keysyms per keycode, keycodes from 8: 8 → (a, A), 9 → (space, -), 10 → (n, N).
  const std::vector<std::uint32_t> table = {0x61, 0x41, 0x20, 0, 0x6e, 0x4e};
  EXPECT_EQ(x11::keycodeFor(table, 2, 8, 0x20), 9);
  EXPECT_EQ(x11::keycodeFor(table, 2, 8, 0x6e), 10);
  EXPECT_EQ(x11::keycodeFor(table, 2, 8, 0x4e), 10);
  EXPECT_EQ(x11::keycodeFor(table, 2, 8, 0x7a), 0) << "no key makes a z";
  EXPECT_EQ(x11::keycodeFor(table, 0, 8, 0x20), 0);
}

TEST(X11Keys, PortalTriggerNotation) {
  EXPECT_EQ(x11::portalTrigger(Qt::Key_Space, Qt::ControlModifier | Qt::ShiftModifier), QStringLiteral("CTRL+SHIFT+space"));
  EXPECT_EQ(x11::portalTrigger(Qt::Key_N, Qt::ControlModifier | Qt::ShiftModifier), QStringLiteral("CTRL+SHIFT+n"));
  EXPECT_EQ(x11::portalTrigger(Qt::Key_F5, Qt::AltModifier | Qt::MetaModifier), QStringLiteral("ALT+LOGO+F5"));
  EXPECT_EQ(x11::portalTrigger(Qt::Key_VolumeUp, Qt::ControlModifier), QString());
}
