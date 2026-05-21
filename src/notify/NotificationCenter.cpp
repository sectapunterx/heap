#include "NotificationCenter.h"

#include <QtGlobal>

namespace heap::notify {

// Forward declarations of platform-specific factories. Each lives in its own
// .cpp; the linker pulls only the one matching the current platform.
#if defined(Q_OS_LINUX)
std::unique_ptr<NotificationCenter> createLinuxDBus(QObject *parent);
#endif
std::unique_ptr<NotificationCenter> createTrayFallback(QObject *parent);

std::unique_ptr<NotificationCenter> NotificationCenter::create(QObject *parent) {
#if defined(Q_OS_LINUX)
    if (auto n = createLinuxDBus(parent)) {
        return n;
    }
#endif
    // Windows + macOS + any environment without an available DBus session.
    return createTrayFallback(parent);
}

} // namespace heap::notify
