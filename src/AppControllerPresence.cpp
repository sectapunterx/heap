// heap staying around: start at login (APP-154).
#include "AppController.h"

#include "platform/Autostart.h"

#include <QJsonDocument>
#include <QJsonObject>

QVariantMap AppController::autostartState() const {
  namespace as = heap::platform::autostart;
  const as::Entry entry = as::read();
  const QVariantMap sys = settingsMap().value(QStringLiteral("system")).toMap();
  QVariantMap out;
  out[QStringLiteral("supported")] = as::supported();
  out[QStringLiteral("enabled")] = entry.enabled;
  out[QStringLiteral("minimized")] = entry.enabled ? entry.minimized : sys.value(QStringLiteral("startMinimized"), false).toBool();
  return out;
}

bool AppController::setAutostart(bool enabled, bool minimized) {
  namespace as = heap::platform::autostart;
  const bool ok = as::write(enabled, minimized);
  if(!ok) {
    emit toast(tr_("settings.system.startAtLogin.failed"), QStringLiteral("error"));
  }

  QJsonObject root = QJsonDocument::fromJson(m_appSettingsJson.toUtf8()).object();
  QJsonObject sys = root.value(QStringLiteral("system")).toObject();
  sys[QStringLiteral("startAtLogin")] = as::read().enabled;
  sys[QStringLiteral("startMinimized")] = minimized;
  // A login start is pointless if the first close quits heap again; only an
  // unanswered question is answered here, never the user's own "quit".
  if(enabled && ok && !sys.contains(QStringLiteral("closeToTray"))) {
    sys[QStringLiteral("closeToTray")] = true;
  }
  root[QStringLiteral("system")] = sys;
  setAppSettingsJson(QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact)));
  return ok;
}
