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

// The task half of a task reminder's id names the profile too (PRES-2): a task
// id is unique only inside its profile, and "deadline:TASK-3" alone made Done
// act on whichever profile had a TASK-3 first, the active one.
//   taskRef("work", "TASK-3")    → "work/TASK-3"  (so "deadline:work/TASK-3")
//   parseTaskRef("work/TASK-3")  → {"work", "TASK-3"}
//   parseTaskRef("TASK-3")       → {"", "TASK-3"}  (a toast or snooze from before)
// A slash cannot be in a new task id; a profile id that has one is left out
// rather than misread.
inline QString taskRef(const QString& profileId, const QString& taskId) {
  if(profileId.isEmpty() || profileId.contains(QChar('/'))) {
    return taskId;
  }
  return profileId + QChar('/') + taskId;
}

inline std::pair<QString, QString> parseTaskRef(const QString& ref) {
  const int sep = ref.indexOf(QChar('/'));
  if(sep <= 0 || sep == ref.size() - 1) {
    return {{}, ref};
  }
  return {ref.left(sep), ref.mid(sep + 1)};
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
//   Windows → WinRT toasts with buttons through the MinGW-w64 ABI headers
//             (NotificationCenter_win.cpp); clicks come back as heap://notify
//             URIs (protocol activation) and reach handleActivationUri().
//   macOS  → UNUserNotificationCenter with a category of buttons
//             (NotificationCenter_mac.mm); needs a real .app bundle.
// Windows and macOS keep the tray icon for presence, and fall back to its
// balloon (no buttons) when the native path is unavailable — always so in
// Qt's test mode, so a test run never registers anything with the OS.
class NotificationCenter : public QObject {
  Q_OBJECT
 public:
  static std::unique_ptr<NotificationCenter> create(QObject* parent);
  // Off: create() keeps to the tray even where a native backend exists.
  // `heap --smoke` turns it off, so a health check registers nothing with
  // the OS (Qt's test mode does the same for the test suites).
  static void setNativeAllowed(bool allowed);
  ~NotificationCenter() override = default;

  virtual void post(const Notification& n) = 0;
  virtual void dismiss(const QString& id) = 0;
  // True when the backend actually renders action buttons. Callers may
  // skip producing actions when this is false to avoid misleading toasts.
  virtual bool supportsActions() const = 0;

  // A heap://notify URI a click came back with (Windows protocol activation,
  // forwarded by the launch the shell started). Emits activated() or
  // actionInvoked() and returns true; false for anything else.
  bool handleActivationUri(const QString& uri);

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
