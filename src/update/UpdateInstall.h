#pragma once

#include "update/Updater.h"

#include <QString>

// Putting a downloaded, checksum-verified update in place (APP-125).
//
// Windows: heap copies heap-updater.exe to the temp folder and starts it; it
//   waits for heap to quit, runs the new installer silently (setup) or unpacks
//   the zip over the folder (portable), and starts heap again.
// macOS / Linux: a running program's files can be replaced there, so heap
//   swaps heap.app (from the dmg) or the AppImage itself, then leaves a shell
//   waiting for it to quit to start the new one.
//
// Either way the caller quits right after startInstall() returns true.
namespace heap::update {

// The running copy of heap, as detectPackageKind() needs it.
PackageEnv currentPackageEnv();

// Where downloads and the outcome file live: <temp>/heap-update.
QString updateWorkDir();

// Start installing `package` (already verified). Returns
// false, and why, if nothing was started; heap keeps running then.
bool startInstall(PackageKind kind, const QString& package, QString& error);

// What the install a previous run started came to. Read once: the outcome
// file is removed, so the next start does not report it again.
struct InstallOutcome {
  bool present = false;
  bool ok = false;
  QString error;
};

InstallOutcome takeInstallOutcome();

// Parse an outcome file's text ("ok" / "error\n<why>"). Pure — unit-tested.
InstallOutcome parseInstallOutcome(const QByteArray& text);

}  // namespace heap::update
