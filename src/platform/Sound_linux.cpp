#include "platform/Sound.h"

#include <QDir>
#include <QFile>
#include <QHash>
#include <QProcess>
#include <QStandardPaths>
#include <QStringList>

namespace heap::platform::detail {

namespace {

// Each buffer written once to the cache directory, as <key>.wav: the players
// take a path.
QString cachedWavPath(const QByteArray& wav, const QString& key) {
  static QHash<QString, QString> paths;
  const auto known = paths.constFind(key);
  if(known != paths.constEnd()) {
    return *known;
  }
  const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/sounds");
  if(!QDir().mkpath(dir)) {
    return {};
  }
  QFile out(QDir(dir).filePath(key + QStringLiteral(".wav")));
  if(!out.open(QIODevice::WriteOnly | QIODevice::Truncate) || out.write(wav) != wav.size()) {
    return {};
  }
  paths.insert(key, out.fileName());
  return out.fileName();
}

}  // namespace

bool playWav(const QByteArray& wav, const QString& key) {
  const QString file = cachedWavPath(wav, key);
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

bool systemBusy() {
  // No desktop-neutral "do not disturb" to ask; heap's own quiet hours and
  // focus mode still apply.
  return false;
}

}  // namespace heap::platform::detail
