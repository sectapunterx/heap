#include "NotificationCenter.h"

#include <QAction>
#include <QGuiApplication>
#include <QIcon>
#include <QMenu>
#include <QStyleHints>
#include <QSystemTrayIcon>

namespace heap::notify {

namespace {

// The tray shows the glyph alone, in one colour (APP-280): the full app icon
// with its tile turns to mush at 16 px on a taskbar. macOS recolours a
// template image for the menu bar itself; elsewhere the glyph is white on a
// dark taskbar or panel and near-black on a light one.
QIcon trayIcon() {
#ifdef Q_OS_MACOS
  QIcon icon(QStringLiteral(":/brand/lowkey/lowkey-tray-template.svg"));
  icon.setIsMask(true);
#else
  // colorScheme() is Qt 6.5+; the clang-tidy job builds against the distro's
  // older Qt, where a dark panel is the safer guess.
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
  const bool dark = QGuiApplication::styleHints()->colorScheme() != Qt::ColorScheme::Light;
#else
  const bool dark = true;
#endif
  QIcon icon(dark ? QStringLiteral(":/brand/lowkey/lowkey-tray-light.svg") : QStringLiteral(":/brand/lowkey/lowkey-tray-dark.svg"));
#endif
  return icon.isNull() ? QGuiApplication::windowIcon() : icon;
}

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
    m_tray = new QSystemTrayIcon(trayIcon(), this);
    m_tray->setToolTip(QStringLiteral("lowkey"));

    // Context menu so the app is controllable while running windowless (the
    // window hides to the tray on close). QMenu needs QtWidgets, which the app
    // already links. Parented to no widget — QSystemTrayIcon owns it via
    // setContextMenu.
    auto* menu = new QMenu();
    QAction* showAction = menu->addAction(QStringLiteral("Show lowkey"));
    connect(showAction, &QAction::triggered, this, [this]() {
      emit showWindowRequested();
    });
    menu->addSeparator();
    QAction* quitAction = menu->addAction(QStringLiteral("Quit"));
    connect(quitAction, &QAction::triggered, this, [this]() {
      emit quitRequested();
    });
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
