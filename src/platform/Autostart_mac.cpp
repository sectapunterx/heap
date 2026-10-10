#include "platform/Autostart.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>

namespace heap::platform::autostart::detail {

namespace {

// ~/Library/LaunchAgents/<label>.plist, or the same path under the test root.
QString agentPath(const QString& root, const char* label = kMacLabel) {
  const QString home = root.isEmpty() ? QDir::homePath() : root;
  return home + QStringLiteral("/Library/LaunchAgents/") + QLatin1String(label) + QStringLiteral(".plist");
}

}  // namespace

Entry readSystem(const QString& root) {
  QFile f(agentPath(root));
  if(!f.open(QIODevice::ReadOnly)) {
    return {};
  }
  return parseMacLaunchAgent(QString::fromUtf8(f.readAll()));
}

bool writeSystem(const QString& root, bool enabled, bool minimized) {
  const QString path = agentPath(root);
  QFile::remove(agentPath(root, kLegacyMacLabel));  // heap 0.7's agent: one start, never two
  if(!enabled) {
    return !QFile::exists(path) || QFile::remove(path);
  }
  QDir().mkpath(QFileInfo(path).absolutePath());
  QSaveFile f(path);
  if(!f.open(QIODevice::WriteOnly)) {
    return false;
  }
  // The binary inside the bundle: launchd runs it directly.
  f.write(macLaunchAgentPlist(QLatin1String(kMacLabel), QCoreApplication::applicationFilePath(), minimized).toUtf8());
  return f.commit();
}

Entry readLegacySystem(const QString& root) {
  QFile f(agentPath(root, kLegacyMacLabel));
  if(!f.open(QIODevice::ReadOnly)) {
    return {};
  }
  return parseMacLaunchAgent(QString::fromUtf8(f.readAll()));
}

void removeLegacySystem(const QString& root) {
  QFile::remove(agentPath(root, kLegacyMacLabel));
}

}  // namespace heap::platform::autostart::detail
