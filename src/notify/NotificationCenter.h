#pragma once

#include <QObject>
#include <QString>
#include <QVector>

#include <memory>
#include <utility>

namespace heap::notify {

// ── Routing helpers ─────────────────────────────────────────────────
// Pack/unpack a `<kind>:<taskId>` notification id. Defined here so they
// can be unit-tested without pulling in QtDBus / QtGui.
//   routingId("deadline", "LTE-2398")  → "deadline:LTE-2398"
//   routingId("",         "LTE-2398")  → "task:LTE-2398"  (sane fallback)
//   parseRoutingId("deadline:LTE-2398") → {"deadline", "LTE-2398"}
//   parseRoutingId("no-colon")          → {"", ""}        (malformed)
inline QString routingId(const QString& kind, const QString& taskId) {
  return (kind.isEmpty() ? QStringLiteral("task") : kind) + QChar(':') + taskId;
}

inline std::pair<QString, QString> parseRoutingId(const QString& id) {
  const int sep = id.indexOf(QChar(':'));
  if(sep <= 0 || sep == id.size() - 1) {
    return {{}, {}};
  }
  return {id.left(sep), id.mid(sep + 1)};
}

struct NotificationAction {
  QString id;     // stable identifier — "snooze1h" / "done" / "open"
  QString label;  // user-visible button text
};

struct Notification {
  QString id;  // re-use to update / dismiss the toast
  QString title;
  QString body;
  QString iconPath;  // resource path or absolute fs path
  QVector<NotificationAction> actions;
  QString category;     // "deadline" | "standup" | "git" …
  int durationSec = 0;  // 0 = OS default
};

// OS-native notification surface. Created via `create(parent)` which picks
// the best available backend:
//   Linux  → org.freedesktop.Notifications (DBus). Supports action buttons.
//   Windows → QSystemTrayIcon balloon fallback. Actions are NOT supported by
//             the legacy Shell_NotifyIcon API; full WinRT
//             ToastNotificationManager would require Windows SDK headers
//             that MSYS2/MinGW doesn't ship by default.
//   macOS  → fallback to tray-balloon for now. UNUserNotificationCenter
//             requires an Objective-C++ implementation (post-release item).
class NotificationCenter : public QObject {
  Q_OBJECT
 public:
  static std::unique_ptr<NotificationCenter> create(QObject* parent);
  ~NotificationCenter() override = default;

  virtual void post(const Notification& n) = 0;
  virtual void dismiss(const QString& id) = 0;
  // True when the backend actually renders action buttons. Callers may
  // skip producing actions when this is false to avoid misleading toasts.
  virtual bool supportsActions() const = 0;

 signals:
  void actionInvoked(const QString& notificationId, const QString& actionId);
  void dismissed(const QString& notificationId);
  // Emitted when the user clicks the toast body (default activation).
  void activated(const QString& notificationId);
  // Tray-icon presence signals (only the tray backend emits these). The app
  // uses them to run windowless: restore the window on a tray click / "Show",
  // and exit for real on "Quit". Backends without a tray never emit them.
  void showWindowRequested();
  void quitRequested();

 protected:
  using QObject::QObject;
};

}  // namespace heap::notify
