#include "platform/Sound.h"

#include <QFile>
#include <QLoggingCategory>
#include <QStandardPaths>
#include <QtEndian>

#include <algorithm>
#include <array>
#include <atomic>
#include <functional>
#include <map>
#include <utility>

Q_LOGGING_CATEGORY(lcSound, "heap.sound")

namespace heap::platform {

namespace {

std::atomic<bool> g_suppressed{false};
std::array<std::atomic<int>, kSoundCueCount> g_requests{};

constexpr qsizetype kWavHeader = 44;

}  // namespace

SoundSettings soundSettingsFrom(const QVariantMap& appSettings) {
  SoundSettings s;
  const QVariantMap sound = appSettings.value(QStringLiteral("sound")).toMap();
  s.enabled = sound.value(QStringLiteral("enabled"), false).toBool();
  bool ok = false;
  const int volume = sound.value(QStringLiteral("volume")).toInt(&ok);
  s.volume = ok ? std::clamp(volume, 0, 100) : kDefaultSoundVolume;
  s.meetingChimes = sound.value(QStringLiteral("meetingChimes"), true).toBool();
  // Up to three moments, latest first, each 1–120 minutes; anything unusable
  // keeps the default.
  if(sound.contains(QStringLiteral("meetingChimeMinutes"))) {
    QList<int> minutes;
    for(const QVariant& v : sound.value(QStringLiteral("meetingChimeMinutes")).toList()) {
      bool isInt = false;
      const int m = v.toInt(&isInt);
      if(isInt && m >= 1 && m <= kMaxChimeMinutes && !minutes.contains(m)) {
        minutes.append(m);
      }
    }
    std::sort(minutes.begin(), minutes.end(), std::greater<>());
    if(!minutes.isEmpty()) {
      s.chimeMinutes = minutes.mid(0, 3);
    }
  }
  return s;
}

bool migrateLegacySoundSetting(QJsonObject& app) {
  QJsonObject appearance = app.value(QStringLiteral("appearance")).toObject();
  if(!appearance.contains(QStringLiteral("completionSound"))) {
    return false;
  }
  const bool legacy = appearance.value(QStringLiteral("completionSound")).toBool();
  appearance.remove(QStringLiteral("completionSound"));
  app.insert(QStringLiteral("appearance"), appearance);
  QJsonObject sound = app.value(QStringLiteral("sound")).toObject();
  // A switch already set in the new place wins over the old one.
  if(!sound.contains(QStringLiteral("enabled"))) {
    sound.insert(QStringLiteral("enabled"), legacy);
  }
  app.insert(QStringLiteral("sound"), sound);
  return true;
}

bool shouldPlayCompletionSound(const QString& fromStatus, const QString& toStatus, StatusChangeSource source, bool enabled) {
  if(!enabled || source != StatusChangeSource::User) {
    return false;
  }
  const QString done = QLatin1String(kDoneStatusId);
  return toStatus == done && fromStatus != done;
}

bool soundAllowed(const SoundSettings& settings, bool quietHours, bool focusMode, bool busy) {
  return settings.enabled && settings.volume > 0 && !quietHours && !focusMode && !busy;
}

const char* cueName(SoundCue cue) {
  switch(cue) {
    case SoundCue::Done:
      return "done";
    case SoundCue::Undo:
      return "undo";
    case SoundCue::Refuse:
      return "refuse";
    case SoundCue::MeetChords:
      return "meet-chords";
    case SoundCue::MeetRise:
      return "meet-rise";
    case SoundCue::MeetCall:
      return "meet-call";
  }
  return "done";
}

const QByteArray& cueWav(SoundCue cue) {
  static const std::array<QByteArray, kSoundCueCount> wavs = []() {
    std::array<QByteArray, kSoundCueCount> out;
    for(int i = 0; i < kSoundCueCount; ++i) {
      const auto c = static_cast<SoundCue>(i);
      QFile f(QStringLiteral(":/sounds/%1.wav").arg(QLatin1String(cueName(c))));
      out.at(static_cast<size_t>(c)) = f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
    }
    return out;
  }();
  return wavs.at(static_cast<size_t>(cue));
}

QByteArray scaledWav(const QByteArray& wav, int volume) {
  if(wav.size() <= kWavHeader || wav.left(4) != "RIFF" || wav.mid(36, 4) != "data" ||
     qFromLittleEndian<quint16>(wav.constData() + 34) != 16) {
    return wav;
  }
  const double gain = std::clamp(volume, 0, 100) / 100.0;
  QByteArray out = wav;
  char* d = out.data();
  for(qsizetype i = kWavHeader; i + 1 < out.size(); i += 2) {
    const auto s = static_cast<double>(qFromLittleEndian<qint16>(d + i));
    qToLittleEndian<qint16>(static_cast<qint16>(std::lround(s * gain)), d + i);
  }
  return out;
}

bool systemBusy() {
  if(QStandardPaths::isTestModeEnabled()) {
    return false;
  }
  return detail::systemBusy();
}

void setSoundSuppressed(bool suppressed) {
  g_suppressed = suppressed;
}

int soundRequestCount(SoundCue cue) {
  return g_requests.at(static_cast<size_t>(cue)).load();
}

void playCue(SoundCue cue, int volume) {
  ++g_requests.at(static_cast<size_t>(cue));
  if(g_suppressed || QStandardPaths::isTestModeEnabled() || volume <= 0) {
    return;
  }
  try {
    const QByteArray& wav = cueWav(cue);
    if(wav.isEmpty()) {
      qCDebug(lcSound, "sound: no bundled wav for %s", cueName(cue));
      return;
    }
    // The backends read the bytes in place while the sound plays (Windows'
    // SND_MEMORY), so each (cue, volume) buffer is kept for the life of the
    // process — a handful, a dozen KB each (under 90 KB for a chime).
    const int v = std::clamp(volume, 1, 100);
    static std::map<std::pair<int, int>, QByteArray> scaled;
    auto it = scaled.find({static_cast<int>(cue), v});
    if(it == scaled.end()) {
      it = scaled.emplace(std::make_pair(static_cast<int>(cue), v), scaledWav(wav, v)).first;
    }
    const QString key = QStringLiteral("%1-%2").arg(QLatin1String(cueName(cue))).arg(v);
    const bool ok = detail::playWav(it->second, key);
    qCDebug(lcSound, "sound %s: %s", qPrintable(key), ok ? "played" : "not played");
  } catch(...) {
    qCDebug(lcSound, "sound: playback threw");
  }
}

}  // namespace heap::platform
