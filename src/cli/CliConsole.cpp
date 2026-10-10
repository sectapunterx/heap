#include "cli/CliConsole.h"
#include "platform/Brand.h"

#include <QCoreApplication>

#include <cstdio>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#ifndef HEAP_VERSION
#define HEAP_VERSION "0.0.0-dev"
#endif

namespace heap::cli {

void attachConsole() {
#ifdef Q_OS_WIN
  if(!AttachConsole(ATTACH_PARENT_PROCESS)) {
    return;  // no console to borrow (git-bash's mintty, a service); pipes still work
  }
  for(const DWORD which : {STD_OUTPUT_HANDLE, STD_ERROR_HANDLE}) {
    HANDLE h = GetStdHandle(which);
    if(h == nullptr || h == INVALID_HANDLE_VALUE) {
      h = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
      if(h != INVALID_HANDLE_VALUE) {
        SetStdHandle(which, h);
      }
    }
  }
#endif
}

void write(bool toErr, const QString& text) {
  if(text.isEmpty()) {
    return;
  }
#ifdef Q_OS_WIN
  HANDLE h = GetStdHandle(toErr ? STD_ERROR_HANDLE : STD_OUTPUT_HANDLE);
  if(h == nullptr || h == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD mode = 0;
  DWORD written = 0;
  if(GetConsoleMode(h, &mode) != 0) {
    WriteConsoleW(h, reinterpret_cast<const wchar_t*>(text.utf16()), static_cast<DWORD>(text.size()), &written, nullptr);
    return;
  }
  const QByteArray bytes = text.toUtf8();
  WriteFile(h, bytes.constData(), static_cast<DWORD>(bytes.size()), &written, nullptr);
#else
  const QByteArray bytes = text.toUtf8();
  std::FILE* f = toErr ? stderr : stdout;
  std::fwrite(bytes.constData(), 1, static_cast<std::size_t>(bytes.size()), f);
  std::fflush(f);
#endif
}

int report(const Response& r) {
  write(false, r.out);
  write(true, r.err);
  return r.exitCode;
}

int usage(const QString& message) {
  write(true, QStringLiteral("lowkey: %1\nRun 'lowkey help' for usage.\n").arg(message));
  return kExitUsage;
}

void quietMessages(QtMsgType, const QMessageLogContext&, const QString&) {
}

void setApplicationIdentity() {
  QCoreApplication::setOrganizationName(QLatin1String(heap::brand::kName));
  QCoreApplication::setOrganizationDomain(QStringLiteral("lowkey.local"));
  QCoreApplication::setApplicationName(QLatin1String(heap::brand::kName));
  QCoreApplication::setApplicationVersion(QStringLiteral(HEAP_VERSION));
}

}  // namespace heap::cli
