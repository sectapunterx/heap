#include "platform/Autostart.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>

namespace heap::platform::autostart::detail {

namespace {

// $XDG_CONFIG_HOME/autostart/heap.desktop, or .config/autostart under the
// test root.
QString entryPath(const QString& root) {
  const QString config =
      root.isEmpty() ? QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) : root + QStringLiteral("/.config");
  return config + QStringLiteral("/autostart/heap.desktop");
}

}  // namespace

Entry readSystem(const QString& root) {
  QFile f(entryPath(root));
  if(!f.open(QIODevice::ReadOnly)) {
    return {};
  }
  return parseLinuxDesktopEntry(QString::fromUtf8(f.readAll()));
}

bool writeSystem(const QString& root, bool enabled, bool minimized) {
  const QString path = entryPath(root);
  if(!enabled) {
    return !QFile::exists(path) || QFile::remove(path);
  }
  QDir().mkpath(QFileInfo(path).absolutePath());
  QSaveFile f(path);
  if(!f.open(QIODevice::WriteOnly)) {
    return false;
  }
  const QString exec = linuxExecPath(qEnvironmentVariable("APPIMAGE"), QCoreApplication::applicationFilePath());
  f.write(linuxDesktopEntry(exec, minimized).toUtf8());
  return f.commit();
}

}  // namespace heap::platform::autostart::detail
