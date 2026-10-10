#pragma once

#include <QString>
#include <QStringList>
#include <Qt>

// Keys as the 0.8.0 keymap (keymap.md, APP-272/279) names and reads them.
// Pure functions: no event plumbing, no settings — KeyRouter and
// AppController call them, the tests call them directly.
namespace heap::keys {

// Which native key code a platform reports, for reading the physical key.
enum class NativeKeys {
  None,     // offscreen, a test, an unknown platform: the key and its text only
  Windows,  // nativeVirtualKey is the VK code (positional for Cyrillic layouts)
  Mac,      // nativeVirtualKey is the kVK code (positional)
  X11,      // nativeScanCode is the X keycode (evdev + 8, positional)
};

NativeKeys nativeKeysFor(const QString& platformName);

// What the person pressed, as the catalogue spells a single chord in
// QKeySequence::PortableText: "G", "Shift+G", "Ctrl+K", "?", ":", "Return".
// Empty for a lone modifier or a key there is no name for.
//
// Letters and digits are read by the physical key wherever the layout does not
// type Latin letters: "п" (on the G key of ЙЦУКЕН) is "G", Ctrl+Л is "Ctrl+K".
// The native code is used when the platform has one; otherwise a Cyrillic
// letter is mapped by the ЙЦУКЕН table. Punctuation follows the layout when
// it types Latin (a German "#" stays "#") and the physical key otherwise
// (the Russian "." on the "/" key is "/"). A shifted punctuation key is the
// character it makes on a US layout: Shift + "/" is "?", Shift + ";" is ":".
struct KeyInput {
  int key = 0;
  Qt::KeyboardModifiers modifiers;
  QString text;
  quint32 nativeVirtualKey = 0;
  quint32 nativeScanCode = 0;
};

QString chordFor(const KeyInput& in, NativeKeys native, bool latinLayout);

// "G, B" → {"G", "B"}.
QStringList chordsOf(const QString& portable);

// A chord with no Ctrl, Alt or Meta: a key that only means something while
// the focus is in the content, never while typing.
bool isBareChord(const QString& chord);
// A sequence that is one bare chord or more than one chord — the ones
// KeyRouter answers rather than a Qt Shortcut.
bool isRouterSequence(const QString& portable);

// True when one sequence is the other's leading chords ("G" and "G, B"):
// the shorter would fire before the longer could be typed.
bool isPrefixOf(const QString& shorter, const QString& longer);

// How a key is written next to its action (keymap.md): a lowercase letter
// is the key without Shift, Shift is a word, the chords of a sequence are
// separated by a space — "d", "Shift S", "g b", "Ctrl K", "Enter", "Esc",
// "Del". On macOS the modifiers are the system's own glyphs ("⇧⌘K").
QString displayKeys(const QString& portable, bool mac);

// Why a key cannot be given to an action — the system keeps it, or it is how
// every dialog and field is driven. Empty when the key is free to bind.
// Returns a stable code ("system", "navigation"), not text.
QString reservedReason(const QString& portable);

}  // namespace heap::keys
