#include "platform/Sound.h"

#include <QDir>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>
#include <QStringList>

namespace heap::platform::detail {

namespace {

// The WAV written once to the cache directory: the players take a path.
QString cachedWavPath(const QByteArray& wav) {
  static const QString path = [&wav]() -> QString {
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if(dir.isEmpty() || !QDir().mkpath(dir)) {
      return {};
    }
    QFile out(QDir(dir).filePath(QStringLiteral("complete.wav")));
    if(!out.open(QIODevice::WriteOnly | QIODevice::Truncate) || out.write(wav) != wav.size()) {
      return {};
    }
    return out.fileName();
  }();
  return path;
}

}  // namespace

bool playWav(const QByteArray& wav) {
  const QString file = cachedWavPath(wav);
  if(file.isEmpty()) {
    return false;
  }
  // PulseAudio/PipeWire first, plain ALSA next; with neither, stay silent —
  // the terminal bell is not what anybody asked for.
  const QString paplay = QStandardPaths::findExecutable(QStringLiteral("paplay"));
  if(!paplay.isEmpty()) {
    return QProcess::startDetached(paplay, {file});
  }
  const QString aplay = QStandardPaths::findExecutable(QStringLiteral("aplay"));
  if(!aplay.isEmpty()) {
    return QProcess::startDetached(aplay, {QStringLiteral("-q"), file});
  }
  return false;
}

}  // namespace heap::platform::detail
