#pragma once

#include <QString>

// Start heap when the user logs in (APP-154), so the capture hotkeys and the
// reminders work without opening it by hand first.
//
// Each OS keeps the entry in its own place:
//   Windows → HKCU\Software\Microsoft\Windows\CurrentVersion\Run, value "heap"
//   macOS   → ~/Library/LaunchAgents/<bundle id>.plist with RunAtLoad
//   Linux   → ~/.config/autostart/heap.desktop (the AppImage when run from one)
//
// The OS entry is the truth: read() looks at it, so Settings shows what will
// really happen at the next login, also after the user removed it by hand.
//
// The text of each entry is built and parsed by the pure helpers below, which
// the tests cover on every platform. Only read()/write() touch the system, and
// they go to a scratch folder instead whenever a test root is set or Qt's
// test mode is on, so a test run never edits the real login items.
namespace heap::platform::autostart {

// What the entry says. `minimized` is only meaningful while `enabled`.
struct Entry {
  bool enabled = false;
  bool minimized = false;
};

// The flag a login start passes: heap comes up hidden in the tray.
inline constexpr char kMinimizedFlag[] = "--minimized";

// Identifier of the macOS launch agent; the bundle's own identifier.
inline constexpr char kMacLabel[] = "local.heap.app";

// ── Pure helpers ────────────────────────────────────────────────────
// Windows: the Run value, `"C:\path\heap.exe" --minimized`.
QString windowsRunCommand(const QString& exePath, bool minimized);
Entry parseWindowsRunCommand(const QString& value);

// macOS: a launch agent that runs `program` once at login.
QString macLaunchAgentPlist(const QString& label, const QString& program, bool minimized);
Entry parseMacLaunchAgent(const QString& plist);

// Linux: an XDG autostart entry.
QString linuxDesktopEntry(const QString& execPath, bool minimized);
Entry parseLinuxDesktopEntry(const QString& text);
// What to launch: the AppImage itself when heap runs from one (the binary
// inside lives in a mount point that is gone after a reboot), else the binary.
QString linuxExecPath(const QString& appImageEnv, const QString& applicationPath);

// ── The system entry ────────────────────────────────────────────────
// False where heap has no autostart backend.
bool supported();
Entry read();
// Writes (enabled) or removes (disabled) the entry. True on success.
bool write(bool enabled, bool minimized);

// Point read()/write() at `dir` instead of the real login items (tests).
// Empty restores the default, which in Qt's test mode is a scratch folder too.
void setRootForTesting(const QString& dir);
// The folder read()/write() use in place of the system; empty = the system.
QString testRoot();

namespace detail {
// Per-platform halves, in Autostart_{win,mac,linux}.cpp. `root` is testRoot().
Entry readSystem(const QString& root);
bool writeSystem(const QString& root, bool enabled, bool minimized);
}  // namespace detail

}  // namespace heap::platform::autostart
