#pragma once

#include "cli/CliCore.h"

#include <QString>
#include <QtGlobal>

// Console plumbing for the command line (APP-173).
namespace heap::cli {

// heap.exe is a GUI-subsystem binary on Windows: started from git-bash or with
// its output piped it inherits working handles, but from cmd or PowerShell it
// gets none at all. Then it borrows the parent's console. No-op elsewhere.
void attachConsole();

// Writes to stdout or stderr: UTF-16 to a Windows console (so Cyrillic titles
// survive any code page), UTF-8 to a pipe, a file or a Unix terminal.
void write(bool toErr, const QString& text);

// Prints a response and returns its exit code.
int report(const Response& r);

// "heap: <message>" plus a pointer to `heap help`, exit code kExitUsage.
int usage(const QString& message);

// A message handler that drops everything: Qt's own chatter (a socket that
// found no server) is not the command's output.
void quietMessages(QtMsgType type, const QMessageLogContext& context, const QString& message);

// Sets the organization/application names the window uses, so paths resolve
// to the same folders.
void setApplicationIdentity();

}  // namespace heap::cli
