#pragma once

// The product's name in every place the OS or another program sees it
// (APP-280: heap → lowkey, owner's call 2026-10-08). Always lowercase. The
// legacy names stay readable so a 0.7.x install moves over without losing
// anything: its data folder, its keychain entries, its heap:// links.
namespace heap::brand {

// Application and organisation name: the data folder is <AppData>/lowkey/lowkey.
inline constexpr char kName[] = "lowkey";
inline constexpr char kLegacyName[] = "heap";

// Where integration tokens live in the OS keychain.
inline constexpr char kKeychainService[] = "lowkey.integrations";
inline constexpr char kLegacyKeychainService[] = "heap.integrations";

// The OS URL scheme toast clicks come back through. heap:// is still
// accepted: a notification shown by 0.7.x may sit in the Action Center.
inline constexpr char kUrlScheme[] = "lowkey";
inline constexpr char kLegacyUrlScheme[] = "heap";

// The lock that makes one running copy per data folder.
inline constexpr char kLockFile[] = "lowkey.lock";
inline constexpr char kLegacyLockFile[] = "heap.lock";

// Left in the old data folder once its contents were copied to the new one.
inline constexpr char kMovedMarker[] = "MOVED-TO-LOWKEY.txt";

}  // namespace heap::brand
