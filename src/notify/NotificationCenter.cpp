#include "NotificationCenter.h"

#include <QStandardPaths>
#include <QtGlobal>

namespace heap::notify {

// Forward declarations of platform-specific factories. Each lives in its own
// .cpp; the linker pulls only the one matching the current platform.
#if defined(Q_OS_LINUX)
std::unique_ptr<NotificationCenter> createLinuxDBus(QObject* parent);
#elif defined(Q_OS_WIN)
std::unique_ptr<NotificationCenter> createWindowsToast(QObject* parent);
#elif defined(Q_OS_MACOS)
std::unique_ptr<NotificationCenter> createMacNative(QObject* parent);
#endif
std::unique_ptr<NotificationCenter> createTrayFallback(QObject* parent);

namespace {
bool& nativeAllowed() {
  static bool allowed = true;
  return allowed;
}
}  // namespace

void NotificationCenter::setNativeAllowed(bool allowed) {
  nativeAllowed() = allowed;
}

std::unique_ptr<NotificationCenter> NotificationCenter::create(QObject* parent) {
#if defined(Q_OS_LINUX)
  if(auto n = createLinuxDBus(parent)) {
    return n;
  }
#elif defined(Q_OS_WIN) || defined(Q_OS_MACOS)
  // The native backends register heap with the OS (an AppUserModelID and a
  // URI scheme on Windows, a notification permission on macOS); a test run
  // must not, so it keeps the tray.
  if(nativeAllowed() && !QStandardPaths::isTestModeEnabled()) {
#if defined(Q_OS_WIN)
    if(auto n = createWindowsToast(parent)) {
      return n;
    }
#else
    if(auto n = createMacNative(parent)) {
      return n;
    }
#endif
  }
#endif
  // Any environment without a native backend available.
  return createTrayFallback(parent);
}

}  // namespace heap::notify
