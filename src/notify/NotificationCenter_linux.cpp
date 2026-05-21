#include "NotificationCenter.h"

#include <QHash>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusReply>

namespace heap::notify {

namespace {

// Native Freedesktop notifications backend. Speaks
// `org.freedesktop.Notifications` on the session bus. The Notify method
// supports an `actions` parameter (alternating id / label pairs); the daemon
// emits `ActionInvoked(uint id, string action_key)` when the user clicks
// one. We map the DBus-assigned numeric id back to our string id.
class LinuxDBusBackend : public NotificationCenter {
  Q_OBJECT
 public:
  explicit LinuxDBusBackend(QObject* parent) :
      NotificationCenter(parent),
      m_iface(QStringLiteral("org.freedesktop.Notifications"),
              QStringLiteral("/org/freedesktop/Notifications"),
              QStringLiteral("org.freedesktop.Notifications"),
              QDBusConnection::sessionBus(),
              this) {
    auto bus = QDBusConnection::sessionBus();
    bus.connect(QStringLiteral("org.freedesktop.Notifications"),
                QStringLiteral("/org/freedesktop/Notifications"),
                QStringLiteral("org.freedesktop.Notifications"),
                QStringLiteral("ActionInvoked"),
                this,
                SLOT(onActionInvoked(uint, QString)));
    bus.connect(QStringLiteral("org.freedesktop.Notifications"),
                QStringLiteral("/org/freedesktop/Notifications"),
                QStringLiteral("org.freedesktop.Notifications"),
                QStringLiteral("NotificationClosed"),
                this,
                SLOT(onNotificationClosed(uint, uint)));
  }

  bool supportsActions() const override {
    return true;
  }

  void post(const Notification& n) override {
    QStringList actions;
    // Add "default" so plain body-clicks invoke our `activated` signal.
    actions << QStringLiteral("default") << QStringLiteral("Open");
    for(const auto& a : n.actions) {
      actions << a.id << a.label;
    }
    QVariantMap hints;
    if(!n.category.isEmpty()) {
      hints[QStringLiteral("category")] = n.category;
    }
    // Suppress system bell for non-critical pings.
    hints[QStringLiteral("urgency")] = uint(1);  // 0 low, 1 normal, 2 critical

    const uint replaceId = m_idMap.value(n.id, 0u);
    const QString iconPath = n.iconPath.isEmpty() ? QStringLiteral("dialog-information") : n.iconPath;
    const int expireMs = n.durationSec > 0 ? n.durationSec * 1000 : -1;

    QDBusReply<uint> reply =
        m_iface.call(QStringLiteral("Notify"), QStringLiteral("heap."), replaceId, iconPath, n.title, n.body, actions, hints, expireMs);

    if(reply.isValid()) {
      const uint dbusId = reply.value();
      // Drop any stale dbus→ourId mapping for the replaced toast.
      for(auto it = m_dbusMap.begin(); it != m_dbusMap.end();) {
        it = (it.value() == n.id) ? m_dbusMap.erase(it) : it + 1;
      }
      m_dbusMap.insert(dbusId, n.id);
      m_idMap.insert(n.id, dbusId);
    }
  }

  void dismiss(const QString& id) override {
    const uint dbusId = m_idMap.value(id, 0u);
    if(dbusId == 0u) {
      return;
    }
    m_iface.call(QStringLiteral("CloseNotification"), dbusId);
  }

 private slots:

  void onActionInvoked(uint dbusId, const QString& actionKey) {
    const QString ourId = m_dbusMap.value(dbusId);
    if(ourId.isEmpty()) {
      return;
    }
    if(actionKey == QStringLiteral("default")) {
      emit activated(ourId);
    } else {
      emit actionInvoked(ourId, actionKey);
    }
  }

  void onNotificationClosed(uint dbusId, uint /*reason*/) {
    const QString ourId = m_dbusMap.take(dbusId);
    if(ourId.isEmpty()) {
      return;
    }
    m_idMap.remove(ourId);
    emit dismissed(ourId);
  }

 private:
  QDBusInterface m_iface;
  QHash<uint, QString> m_dbusMap;  // dbusId → ourId
  QHash<QString, uint> m_idMap;    // ourId  → dbusId
};

}  // namespace

std::unique_ptr<NotificationCenter> createLinuxDBus(QObject* parent) {
  if(!QDBusConnection::sessionBus().isConnected()) {
    return nullptr;
  }
  // The actual `org.freedesktop.Notifications` service is owned by the
  // user's notification daemon (notify-osd, mako, dunst …). If nothing is
  // listening, sending will silently no-op but still succeed — fine.
  return std::make_unique<LinuxDBusBackend>(parent);
}

}  // namespace heap::notify

#include "NotificationCenter_linux.moc"
