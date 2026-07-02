#include "platform/GlobalHotkey.h"

#include <QKeySequence>

#include <gtest/gtest.h>

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
