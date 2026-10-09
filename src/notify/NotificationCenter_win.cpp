#include "NotificationCenter.h"

#include "notify/NotifyPayload.h"
#include "platform/Brand.h"
#include "platform/Paths.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QIcon>
#include <QPixmap>
#include <QSettings>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <wrl/client.h>

#include <roapi.h>
#include <shobjidl.h>
#include <windows.data.xml.dom.h>
#include <windows.h>
#include <windows.ui.notifications.h>
#include <winstring.h>

// Windows toasts with buttons (APP-155), through the WinRT ABI that the
// MinGW-w64 headers ship — no C++/WinRT, no Windows SDK.
//
// An unpackaged app is allowed to show toasts under an AppUserModelID that
// either a Start-menu shortcut carries (the installer's) or that is registered
// under HKCU\Software\Classes\AppUserModelId (what makes the portable zip and
// a dev build work too). Clicks come back by protocol activation: each button
// and the toast itself start a heap://notify URI, which the shell hands to
// heap.exe, which forwards it to the running heap (SingleInstance). That works
// from the Action Center and after heap was closed, which the in-process
// Activated event does not.
//
// Anything failing on the way — no WinRT (Windows 7/8), a refused toast — and
// the notification goes out as the old tray balloon instead.
namespace heap::notify {

std::unique_ptr<NotificationCenter> createTrayFallback(QObject* parent);

namespace {

using Microsoft::WRL::ComPtr;
namespace wun = ABI::Windows::UI::Notifications;
namespace xdom = ABI::Windows::Data::Xml::Dom;

constexpr wchar_t kAppId[] = L"local.lowkey.app";

// An HSTRING for the duration of one call.
class HString {
 public:
  explicit HString(const QString& s) {
    const std::wstring w = s.toStdWString();
    if(FAILED(WindowsCreateString(w.c_str(), static_cast<UINT32>(w.size()), &m_h))) {
      m_h = nullptr;
    }
  }

  explicit HString(const wchar_t* s) {
    if(FAILED(WindowsCreateString(s, static_cast<UINT32>(wcslen(s)), &m_h))) {
      m_h = nullptr;
    }
  }

  ~HString() {
    if(m_h != nullptr) {
      WindowsDeleteString(m_h);
    }
  }

  HString(const HString&) = delete;
  HString& operator=(const HString&) = delete;

  HSTRING get() const {
    return m_h;
  }

 private:
  HSTRING m_h = nullptr;
};

// The user's own heap owns the registrations; a throwaway run (--data-dir)
// only fills in what is missing, so it never repoints the real one at itself.
bool mayOverwriteRegistration() {
  return !heap::paths::dataDirOverridden();
}

// lowkey://… → `"lowkey.exe" "%1"`, so toast clicks reach lowkey. Per user,
// no admin. heap:// is pointed here too: a 0.7.x toast may still sit in the
// Action Center after the upgrade (APP-280).
void registerUriScheme(const QString& scheme) {
  QSettings cls(QStringLiteral(R"(HKEY_CURRENT_USER\Software\Classes\)") + scheme, QSettings::NativeFormat);
  const QString command =
      QStringLiteral("\"%1\" \"%2\"").arg(QDir::toNativeSeparators(QCoreApplication::applicationFilePath()), QStringLiteral("%1"));
  const QString key = QStringLiteral("shell/open/command/Default");
  if(!mayOverwriteRegistration() && !cls.value(key).toString().isEmpty()) {
    return;
  }
  cls.setValue(QStringLiteral("Default"), QStringLiteral("URL:") + scheme);
  cls.setValue(QStringLiteral("URL Protocol"), QString());
  cls.setValue(key, command);
  cls.sync();
}

// The toast header's name and icon, for runs without the installer's shortcut.
void registerAppId(const QString& iconPath) {
  QSettings reg(QStringLiteral(R"(HKEY_CURRENT_USER\Software\Classes\AppUserModelId\)") + QString::fromWCharArray(kAppId),
                QSettings::NativeFormat);
  if(!mayOverwriteRegistration() && !reg.value(QStringLiteral("DisplayName")).toString().isEmpty()) {
    return;
  }
  reg.setValue(QStringLiteral("DisplayName"), QLatin1String(heap::brand::kName));
  if(!iconPath.isEmpty()) {
    reg.setValue(QStringLiteral("IconUri"), QDir::toNativeSeparators(iconPath));
  }
  reg.sync();
}

// A PNG of the app icon next to the data, for the toast's logo (toasts take
// file paths, not Qt resources).
QString toastIconPath() {
  // Named after the brand, so the heap icon a 0.7 install left in the data
  // folder is not reused after the rename.
  return QDir(heap::paths::dataDir()).filePath(QStringLiteral("toast-icon-lowkey.png"));
}

QString ensureToastIcon() {
  if(QFile::exists(toastIconPath())) {
    return toastIconPath();
  }
  QDir().mkpath(heap::paths::dataDir());
  const QPixmap pm = QIcon(QStringLiteral(":/brand/lowkey/lowkey-icon.svg")).pixmap(QSize(96, 96));
  return !pm.isNull() && pm.save(toastIconPath(), "PNG") ? toastIconPath() : QString();
}

class WinToastBackend : public NotificationCenter {
 public:
  explicit WinToastBackend(QObject* parent) : NotificationCenter(parent), m_tray(createTrayFallback(this)) {
    // The tray icon stays: it is heap's presence while the window is hidden,
    // and the balloon is the fallback when a toast cannot be shown.
    connect(m_tray.get(), &NotificationCenter::showWindowRequested, this, &NotificationCenter::showWindowRequested);
    connect(m_tray.get(), &NotificationCenter::quitRequested, this, &NotificationCenter::quitRequested);
    connect(m_tray.get(), &NotificationCenter::activated, this, &NotificationCenter::activated);
  }

  // False when WinRT toasts are not available here.
  bool init() {
    // Qt's main thread is already a COM apartment; RPC_E_CHANGED_MODE only
    // says it is not the one asked for, and WinRT works in either.
    const HRESULT ro = RoInitialize(RO_INIT_SINGLETHREADED);
    if(FAILED(ro) && ro != RPC_E_CHANGED_MODE) {
      return false;
    }
    SetCurrentProcessExplicitAppUserModelID(kAppId);
    m_logo = ensureToastIcon();
    registerAppId(m_logo);
    registerUriScheme(QLatin1String(kUriScheme));
    registerUriScheme(QLatin1String(kLegacyUriScheme));

    ComPtr<wun::IToastNotificationManagerStatics> manager;
    if(FAILED(
           RoGetActivationFactory(HString(RuntimeClass_Windows_UI_Notifications_ToastNotificationManager).get(), IID_PPV_ARGS(&manager)))) {
      return false;
    }
    if(FAILED(manager->CreateToastNotifierWithId(HString(kAppId).get(), &m_notifier))) {
      return false;
    }
    if(FAILED(RoGetActivationFactory(HString(RuntimeClass_Windows_UI_Notifications_ToastNotification).get(), IID_PPV_ARGS(&m_factory)))) {
      return false;
    }
    m_dataDir = heap::paths::dataDirOverridden() ? heap::paths::dataDir() : QString();
    return true;
  }

  void post(const Notification& n) override {
    if(!showToast(n)) {
      qWarning("notify: toast failed, showing a tray balloon instead");
      m_tray->post(n);
    }
  }

  void dismiss(const QString& id) override {
    const ComPtr<wun::IToastNotification> toast = m_shown.take(id);
    if(toast) {
      m_notifier->Hide(toast.Get());
    }
  }

  bool supportsActions() const override {
    return true;
  }

 private:
  bool showToast(const Notification& n) {
    ComPtr<IInspectable> inspectable;
    if(FAILED(RoActivateInstance(HString(RuntimeClass_Windows_Data_Xml_Dom_XmlDocument).get(), &inspectable))) {
      return false;
    }
    ComPtr<xdom::IXmlDocument> doc;
    ComPtr<xdom::IXmlDocumentIO> io;
    if(FAILED(inspectable.As(&doc)) || FAILED(inspectable.As(&io))) {
      return false;
    }
    if(FAILED(io->LoadXml(HString(toastXml(n, m_dataDir, m_logo)).get()))) {
      return false;
    }
    ComPtr<wun::IToastNotification> toast;
    if(FAILED(m_factory->CreateToastNotification(doc.Get(), &toast))) {
      return false;
    }
    // A new toast for the same reminder replaces the one still showing.
    dismiss(n.id);
    if(FAILED(m_notifier->Show(toast.Get()))) {
      return false;
    }
    m_shown.insert(n.id, toast);
    return true;
  }

  std::unique_ptr<NotificationCenter> m_tray;
  ComPtr<wun::IToastNotifier> m_notifier;
  ComPtr<wun::IToastNotificationFactory> m_factory;
  QHash<QString, ComPtr<wun::IToastNotification>> m_shown;
  QString m_logo;
  QString m_dataDir;
};

}  // namespace

std::unique_ptr<NotificationCenter> createWindowsToast(QObject* parent) {
  auto backend = std::make_unique<WinToastBackend>(parent);
  if(!backend->init()) {
    return nullptr;
  }
  return backend;
}

}  // namespace heap::notify
