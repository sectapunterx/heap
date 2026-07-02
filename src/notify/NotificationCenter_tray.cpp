#include "NotificationCenter.h"

#include <QAction>
#include <QGuiApplication>
#include <QIcon>
#include <QMenu>
#include <QSystemTrayIcon>

namespace heap::notify {

namespace {

// Fallback backend: legacy QSystemTrayIcon::showMessage. No action buttons
// (the Shell_NotifyIcon balloon API does not support them). Clicking the
// message body translates to `activated(id)`.
class TrayBackend : public NotificationCenter {
  Q_OBJECT
 public:
  explicit TrayBackend(QObject* parent) : NotificationCenter(parent) {
    if(!QSystemTrayIcon::isSystemTrayAvailable()) {
      return;
    }
    QIcon icon(QStringLiteral(":/brand/icon/heap-icon.svg"));
    if(icon.isNull()) {
      icon = QGuiApplication::windowIcon();
    }
    m_tray = new QSystemTrayIcon(icon, this);
    m_tray->setToolTip(QStringLiteral("heap."));

    // Context menu so the app is controllable while running windowless (the
    // window hides to the tray on close). QMenu needs QtWidgets, which the app
    // already links. Parented to no widget — QSystemTrayIcon owns it via
    // setContextMenu.
    auto* menu = new QMenu();
    QAction* showAction = menu->addAction(QStringLiteral("Show heap."));
    connect(showAction, &QAction::triggered, this, [this]() { emit showWindowRequested(); });
    menu->addSeparator();
    QAction* quitAction = menu->addAction(QStringLiteral("Quit"));
    connect(quitAction, &QAction::triggered, this, [this]() { emit quitRequested(); });
    m_tray->setContextMenu(menu);
    m_menu = menu;

    m_tray->show();
    // A left click / double click on the icon restores the window; a click on a
    // notification balloon still routes to the owning task via activated(id).
    connect(m_tray, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
      if(reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick) {
        emit showWindowRequested();
      }
    });
    connect(m_tray, &QSystemTrayIcon::messageClicked, this, [this]() {
      if(!m_lastId.isEmpty()) {
        emit activated(m_lastId);
      }
    });
  }

  ~TrayBackend() override {
    delete m_menu;
  }

  void post(const Notification& n) override {
    if(!m_tray) {
      return;
    }
    m_lastId = n.id;
    const int ms = n.durationSec > 0 ? n.durationSec * 1000 : 5000;
    m_tray->showMessage(n.title, n.body, QSystemTrayIcon::Information, ms);
  }

  void dismiss(const QString& /*id*/) override {
    // Shell_NotifyIcon balloons time out on their own — no API to dismiss
    // a specific one. Intentionally no-op.
  }

  bool supportsActions() const override {
    return false;
  }

 private:
  QSystemTrayIcon* m_tray{};
  QMenu* m_menu{};
  QString m_lastId;
};

}  // namespace

std::unique_ptr<NotificationCenter> createTrayFallback(QObject* parent) {
  return std::make_unique<TrayBackend>(parent);
}

}  // namespace heap::notify

#include "NotificationCenter_tray.moc"
