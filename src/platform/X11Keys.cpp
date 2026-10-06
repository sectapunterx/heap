#include "platform/X11Keys.h"

#include <QStringList>
#include <Qt>

namespace heap::platform::x11 {

namespace {

// <X11/keysymdef.h> values for the keys a capture hotkey may use.
constexpr std::uint32_t kXkSpace = 0x0020;
constexpr std::uint32_t kXkComma = 0x002c;
constexpr std::uint32_t kXkPeriod = 0x002e;
constexpr std::uint32_t kXkSlash = 0x002f;
constexpr std::uint32_t kXkDigit0 = 0x0030;
constexpr std::uint32_t kXkBackslash = 0x005c;
constexpr std::uint32_t kXkLowerA = 0x0061;
constexpr std::uint32_t kXkTab = 0xff09;
constexpr std::uint32_t kXkReturn = 0xff0d;
constexpr std::uint32_t kXkF1 = 0xffbe;

// The keysym and its name in the XDG shortcuts notation, which uses the xkb
// keysym names.
struct KeyName {
  std::uint32_t keysym = 0;
  QString name;
};

KeyName keyFor(int qt_key) {
  if(qt_key >= Qt::Key_A && qt_key <= Qt::Key_Z) {
    const int offset = qt_key - Qt::Key_A;
    return {.keysym = kXkLowerA + static_cast<std::uint32_t>(offset), .name = QString(QChar(static_cast<char16_t>(u'a' + offset)))};
  }
  if(qt_key >= Qt::Key_0 && qt_key <= Qt::Key_9) {
    const int offset = qt_key - Qt::Key_0;
    return {.keysym = kXkDigit0 + static_cast<std::uint32_t>(offset), .name = QString(QChar(static_cast<char16_t>(u'0' + offset)))};
  }
  if(qt_key >= Qt::Key_F1 && qt_key <= Qt::Key_F24) {
    const int offset = qt_key - Qt::Key_F1;
    return {.keysym = kXkF1 + static_cast<std::uint32_t>(offset), .name = QStringLiteral("F%1").arg(offset + 1)};
  }
  switch(qt_key) {
    case Qt::Key_Space:
      return {.keysym = kXkSpace, .name = QStringLiteral("space")};
    case Qt::Key_Return:
    case Qt::Key_Enter:
      return {.keysym = kXkReturn, .name = QStringLiteral("Return")};
    case Qt::Key_Tab:
      return {.keysym = kXkTab, .name = QStringLiteral("Tab")};
    case Qt::Key_Backslash:
      return {.keysym = kXkBackslash, .name = QStringLiteral("backslash")};
    case Qt::Key_Period:
      return {.keysym = kXkPeriod, .name = QStringLiteral("period")};
    case Qt::Key_Comma:
      return {.keysym = kXkComma, .name = QStringLiteral("comma")};
    case Qt::Key_Slash:
      return {.keysym = kXkSlash, .name = QStringLiteral("slash")};
    default:
      return {};
  }
}

}  // namespace

bool toKeyGrab(int qt_key, int qt_mods, KeyGrab& out) {
  const KeyName key = keyFor(qt_key);
  if(key.keysym == 0) {
    return false;
  }
  unsigned mods = 0;
  if((qt_mods & Qt::ShiftModifier) != 0) {
    mods |= kShiftMask;
  }
  if((qt_mods & Qt::ControlModifier) != 0) {
    mods |= kControlMask;
  }
  if((qt_mods & Qt::AltModifier) != 0) {
    mods |= kMod1Mask;
  }
  if((qt_mods & Qt::MetaModifier) != 0) {
    mods |= kMod4Mask;
  }
  out.keysym = key.keysym;
  out.mods = static_cast<std::uint16_t>(mods);
  return true;
}

QList<std::uint16_t> lockVariants(std::uint16_t mods) {
  return {mods,
          static_cast<std::uint16_t>(mods | kLockMask),
          static_cast<std::uint16_t>(mods | kMod2Mask),
          static_cast<std::uint16_t>(mods | kLockMask | kMod2Mask)};
}

std::uint16_t significantMods(std::uint16_t state) {
  return static_cast<std::uint16_t>(state & (kShiftMask | kControlMask | kMod1Mask | kMod4Mask));
}

std::uint8_t keycodeFor(const std::vector<std::uint32_t>& table, int per_keycode, int min_keycode, std::uint32_t keysym) {
  if(per_keycode <= 0 || keysym == 0) {
    return 0;
  }
  const auto per = static_cast<std::size_t>(per_keycode);
  for(std::size_t i = 0; i < table.size(); ++i) {
    if(table[i] != keysym) {
      continue;
    }
    const auto keycode = static_cast<std::size_t>(min_keycode) + (i / per);
    return keycode <= 255 ? static_cast<std::uint8_t>(keycode) : 0;
  }
  return 0;
}

QString portalTrigger(int qt_key, int qt_mods) {
  const KeyName key = keyFor(qt_key);
  if(key.keysym == 0) {
    return {};
  }
  QStringList parts;
  if((qt_mods & Qt::ControlModifier) != 0) {
    parts << QStringLiteral("CTRL");
  }
  if((qt_mods & Qt::AltModifier) != 0) {
    parts << QStringLiteral("ALT");
  }
  if((qt_mods & Qt::ShiftModifier) != 0) {
    parts << QStringLiteral("SHIFT");
  }
  if((qt_mods & Qt::MetaModifier) != 0) {
    parts << QStringLiteral("LOGO");
  }
  parts << key.name;
  return parts.join(QLatin1Char('+'));
}

}  // namespace heap::platform::x11
