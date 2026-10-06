#include "platform/Sound.h"

#include <QFile>
#include <QLoggingCategory>
#include <QStandardPaths>

#include <atomic>

Q_LOGGING_CATEGORY(lcSound, "heap.sound")

namespace heap::platform {

namespace {

std::atomic<bool> g_suppressed{false};
std::atomic<int> g_requests{0};

}  // namespace

bool shouldPlayCompletionSound(const QString& fromStatus, const QString& toStatus, StatusChangeSource source, bool enabled) {
  if(!enabled || source != StatusChangeSource::User) {
    return false;
  }
  const QString done = QLatin1String(kDoneStatusId);
  return toStatus == done && fromStatus != done;
}

const QByteArray& completionSoundWav() {
  static const QByteArray wav = []() {
    QFile f(QStringLiteral(":/sounds/complete.wav"));
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
  }();
  return wav;
}

void setSoundSuppressed(bool suppressed) {
  g_suppressed = suppressed;
}

int completionSoundRequestCount() {
  return g_requests.load();
}

void playCompletionSound() {
  ++g_requests;
  if(g_suppressed || QStandardPaths::isTestModeEnabled()) {
    return;
  }
  try {
    const QByteArray& wav = completionSoundWav();
    if(wav.isEmpty()) {
      qCDebug(lcSound, "sound: no bundled wav");
      return;
    }
    const bool ok = detail::playWav(wav);
    qCDebug(lcSound, "sound: %s", ok ? "played" : "not played");
  } catch(...) {
    qCDebug(lcSound, "sound: playback threw");
  }
}

}  // namespace heap::platform
