#include "platform/Sound.h"

#include <qt_windows.h>

#include <mmsystem.h>

namespace heap::platform::detail {

bool playWav(const QByteArray& wav) {
  // SND_MEMORY reads the bytes in place for as long as the sound plays, so they
  // must outlive the call: completionSoundWav() is a function-local static.
  // SND_ASYNC returns at once (a new tick cuts the previous one short) and
  // SND_NODEFAULT keeps Windows from substituting its default beep on failure.
  return PlaySoundW(reinterpret_cast<LPCWSTR>(wav.constData()), nullptr, SND_MEMORY | SND_ASYNC | SND_NODEFAULT) != FALSE;
}

}  // namespace heap::platform::detail
