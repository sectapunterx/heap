#include "platform/Sound.h"

#include <qt_windows.h>

#include <mmsystem.h>
#include <shellapi.h>

namespace heap::platform::detail {

bool playWav(const QByteArray& wav, const QString& /*key*/) {
  // SND_MEMORY reads the bytes in place for as long as the sound plays, so they
  // must outlive the call: playCue() keeps every buffer it hands over.
  // SND_ASYNC returns at once (a new sound cuts the previous one short) and
  // SND_NODEFAULT keeps Windows from substituting its default beep on failure.
  return PlaySoundW(reinterpret_cast<LPCWSTR>(wav.constData()), nullptr, SND_MEMORY | SND_ASYNC | SND_NODEFAULT) != FALSE;
}

bool systemBusy() {
  // What Windows tells apps about the user's attention: a presentation, a
  // full-screen game or video, the quiet time after setup. Focus assist's
  // "Do not disturb" has no public API, so heap's own quiet hours stand in.
  QUERY_USER_NOTIFICATION_STATE state{};
  if(FAILED(SHQueryUserNotificationState(&state))) {
    return false;
  }
  return state == QUNS_BUSY || state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_PRESENTATION_MODE || state == QUNS_QUIET_TIME;
}

}  // namespace heap::platform::detail
