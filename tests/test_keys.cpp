// The 0.8.0 keymap's key names and physical-key reading (APP-272/279):
// pure functions in src/keys/KeyNames.
#include "keys/KeyNames.h"

#include <gtest/gtest.h>

using namespace heap::keys;

namespace {

QString chord(int key, Qt::KeyboardModifiers mods = {}, const QString& text = {}, bool latin = true) {
  KeyInput in;
  in.key = key;
  in.modifiers = mods;
  in.text = text;
  return chordFor(in, NativeKeys::None, latin);
}

}  // namespace

TEST(KeyChord, LatinLettersAreTheirKey) {
  EXPECT_EQ(chord(Qt::Key_G, {}, QStringLiteral("g")), QStringLiteral("G"));
  EXPECT_EQ(chord(Qt::Key_G, Qt::ShiftModifier, QStringLiteral("G")), QStringLiteral("Shift+G"));
  EXPECT_EQ(chord(Qt::Key_K, Qt::ControlModifier), QStringLiteral("Ctrl+K"));
  EXPECT_EQ(chord(Qt::Key_1, {}, QStringLiteral("1")), QStringLiteral("1"));
}

TEST(KeyChord, ModifierAloneIsNoChord) {
  EXPECT_TRUE(chord(Qt::Key_Shift, Qt::ShiftModifier).isEmpty());
  EXPECT_TRUE(chord(Qt::Key_Control, Qt::ControlModifier).isEmpty());
}

TEST(KeyChord, CyrillicLettersAreThePhysicalKey) {
  // п и is g b; о is j; Ctrl+Л is Ctrl+K — on ЙЦУКЕН.
  EXPECT_EQ(chord(0x41F, {}, QStringLiteral("п"), false), QStringLiteral("G"));
  EXPECT_EQ(chord(0x418, {}, QStringLiteral("и"), false), QStringLiteral("B"));
  EXPECT_EQ(chord(0x41E, {}, QStringLiteral("о"), false), QStringLiteral("J"));
  EXPECT_EQ(chord(0x41B, Qt::ControlModifier, QString(), false), QStringLiteral("Ctrl+K"));
  EXPECT_EQ(chord(0x41F, Qt::ShiftModifier, QStringLiteral("П"), false), QStringLiteral("Shift+G"));
  // The Latin layout reading is the same for a Cyrillic key: it only ever
  // comes from a Cyrillic layout.
  EXPECT_EQ(chord(0x412, {}, QStringLiteral("в"), true), QStringLiteral("D"));
}

TEST(KeyChord, ShiftedPunctuationIsItsCharacter) {
  EXPECT_EQ(chord(Qt::Key_Question, Qt::ShiftModifier, QStringLiteral("?")), QStringLiteral("?"));
  EXPECT_EQ(chord(Qt::Key_Question, {}, QStringLiteral("?")), QStringLiteral("?"));
  EXPECT_EQ(chord(Qt::Key_Colon, Qt::ShiftModifier, QStringLiteral(":")), QStringLiteral(":"));
  EXPECT_EQ(chord(Qt::Key_Slash, {}, QStringLiteral("/")), QStringLiteral("/"));
  EXPECT_EQ(chord(Qt::Key_Slash, Qt::ShiftModifier, QStringLiteral("?")), QStringLiteral("?"));
}

TEST(KeyChord, RussianPunctuationIsThePhysicalKey) {
  // "." is on the "/" key, "," is Shift + it; "ж" is ";", "Ж" is ":".
  EXPECT_EQ(chord(Qt::Key_Period, {}, QStringLiteral("."), false), QStringLiteral("/"));
  EXPECT_EQ(chord(Qt::Key_Comma, Qt::ShiftModifier, QStringLiteral(","), false), QStringLiteral("?"));
  EXPECT_EQ(chord(0x416, Qt::ShiftModifier, QStringLiteral("Ж"), false), QStringLiteral(":"));
  EXPECT_EQ(chord(0x425, {}, QStringLiteral("х"), false), QStringLiteral("["));
  // On a Latin layout "." is ".".
  EXPECT_EQ(chord(Qt::Key_Period, {}, QStringLiteral("."), true), QStringLiteral("."));
}

TEST(KeyChord, NativeCodesWin) {
  KeyInput in;
  in.key = 0x41F;  // п
  in.text = QStringLiteral("п");
  in.nativeVirtualKey = 0x47;  // VK 'G'
  EXPECT_EQ(chordFor(in, NativeKeys::Windows, false), QStringLiteral("G"));
  in.nativeVirtualKey = 0x05;  // kVK_ANSI_G
  EXPECT_EQ(chordFor(in, NativeKeys::Mac, false), QStringLiteral("G"));
  in.nativeVirtualKey = 0;
  in.nativeScanCode = 42;  // X keycode of G
  EXPECT_EQ(chordFor(in, NativeKeys::X11, false), QStringLiteral("G"));
  // Russian "." on VK_OEM_2 is "/".
  KeyInput dot;
  dot.key = Qt::Key_Period;
  dot.text = QStringLiteral(".");
  dot.nativeVirtualKey = 0xBF;
  EXPECT_EQ(chordFor(dot, NativeKeys::Windows, false), QStringLiteral("/"));
}

TEST(KeyChord, KeysWithoutTextKeepTheirName) {
  EXPECT_EQ(chord(Qt::Key_Escape), QStringLiteral("Esc"));
  EXPECT_EQ(chord(Qt::Key_Return), QStringLiteral("Return"));
  EXPECT_EQ(chord(Qt::Key_Down, Qt::ShiftModifier), QStringLiteral("Shift+Down"));
  EXPECT_EQ(chord(Qt::Key_Delete), QStringLiteral("Del"));
}

TEST(KeySequence, BareAndRouterSequences) {
  EXPECT_TRUE(isBareChord(QStringLiteral("G")));
  EXPECT_TRUE(isBareChord(QStringLiteral("Shift+G")));
  EXPECT_FALSE(isBareChord(QStringLiteral("Ctrl+G")));
  EXPECT_TRUE(isRouterSequence(QStringLiteral("G, B")));
  EXPECT_TRUE(isRouterSequence(QStringLiteral("D")));
  EXPECT_FALSE(isRouterSequence(QStringLiteral("Ctrl+K")));
  EXPECT_FALSE(isRouterSequence(QStringLiteral("Ctrl+,")));
  EXPECT_EQ(chordsOf(QStringLiteral("Ctrl+,")), QStringList{QStringLiteral("Ctrl+,")});
  EXPECT_EQ(chordsOf(QStringLiteral("G, B")), (QStringList{QStringLiteral("G"), QStringLiteral("B")}));
}

TEST(KeySequence, Prefix) {
  EXPECT_TRUE(isPrefixOf(QStringLiteral("G"), QStringLiteral("G, B")));
  EXPECT_FALSE(isPrefixOf(QStringLiteral("G, B"), QStringLiteral("G, B")));
  EXPECT_FALSE(isPrefixOf(QStringLiteral("B"), QStringLiteral("G, B")));
  EXPECT_FALSE(isPrefixOf(QStringLiteral("Shift+G"), QStringLiteral("G, G")));
}

TEST(KeyDisplay, KeymapNotation) {
  EXPECT_EQ(displayKeys(QStringLiteral("D"), false), QStringLiteral("d"));
  EXPECT_EQ(displayKeys(QStringLiteral("Shift+S"), false), QStringLiteral("Shift S"));
  EXPECT_EQ(displayKeys(QStringLiteral("G, B"), false), QStringLiteral("g b"));
  EXPECT_EQ(displayKeys(QStringLiteral("Ctrl+K"), false), QStringLiteral("Ctrl K"));
  EXPECT_EQ(displayKeys(QStringLiteral("Return"), false), QStringLiteral("Enter"));
  EXPECT_EQ(displayKeys(QStringLiteral("Esc"), false), QStringLiteral("Esc"));
  EXPECT_EQ(displayKeys(QStringLiteral("Del"), false), QStringLiteral("Del"));
  EXPECT_EQ(displayKeys(QStringLiteral("Ctrl+Shift+Space"), false), QStringLiteral("Ctrl Shift Space"));
  EXPECT_EQ(displayKeys(QStringLiteral("?"), false), QStringLiteral("?"));
  EXPECT_EQ(displayKeys(QStringLiteral("Ctrl+,"), false), QStringLiteral("Ctrl ,"));
  EXPECT_EQ(displayKeys(QStringLiteral("Ctrl++"), false), QStringLiteral("Ctrl +"));
  EXPECT_EQ(displayKeys(QString(), false), QString());
}

TEST(KeyDisplay, MacGlyphs) {
  EXPECT_EQ(displayKeys(QStringLiteral("Ctrl+K"), true), QStringLiteral("⌘K"));
  EXPECT_EQ(displayKeys(QStringLiteral("Ctrl+Shift+Z"), true), QStringLiteral("⇧⌘Z"));
  EXPECT_EQ(displayKeys(QStringLiteral("Return"), true), QStringLiteral("↩"));
  EXPECT_EQ(displayKeys(QStringLiteral("G, B"), true), QStringLiteral("g b"));
}

TEST(KeyReserved, SystemAndNavigationKeys) {
  EXPECT_EQ(reservedReason(QStringLiteral("Alt+F4")), QStringLiteral("system"));
  EXPECT_EQ(reservedReason(QStringLiteral("Meta+D")), QStringLiteral("system"));
  EXPECT_EQ(reservedReason(QStringLiteral("Tab")), QStringLiteral("navigation"));
  EXPECT_TRUE(reservedReason(QStringLiteral("Ctrl+K")).isEmpty());
  EXPECT_TRUE(reservedReason(QStringLiteral("G, B")).isEmpty());
}
