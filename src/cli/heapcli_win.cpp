// heap-cli (APP-173): the console front door to heap on Windows.
//
// heap.exe is a GUI-subsystem program. cmd and PowerShell start such a program
// and return to the prompt at once: its output lands after the prompt and its
// exit code is lost. heap-cli is a console program, so the shell waits for it:
//
//   heap-cli now | list | today | help   answered here, with only QtCore and
//                                        friends loaded: `now` is fast enough
//                                        for a shell prompt
//   heap-cli add | done | open           run by heap.exe next to it, with this
//                                        console's handles; its exit code is
//                                        passed through
//   heap-cli [--view …]                  starts the window and returns
//
// The verbs, their parsing and their answers are the same code heap.exe runs
// (src/cli).

#include "cli/CliConsole.h"
#include "cli/CliCore.h"
#include "cli/CliQuery.h"
#include "cli/VerbScan.h"
#include "platform/Paths.h"

#include <QCoreApplication>

#include <optional>
#include <string>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

// shellapi.h needs windows.h first.
#include <shellapi.h>

namespace {

// The command line after the program name, exactly as typed, so quoting
// survives the hop to heap.exe.
std::wstring argumentTail() {
  const wchar_t* p = GetCommandLineW();
  if(*p == L'"') {
    ++p;
    while(*p != L'\0' && *p != L'"') {
      ++p;
    }
    if(*p == L'"') {
      ++p;
    }
  } else {
    while(*p != L'\0' && *p != L' ' && *p != L'\t') {
      ++p;
    }
  }
  while(*p == L' ' || *p == L'\t') {
    ++p;
  }
  return p;
}

std::wstring heapExePath() {
  std::wstring self(MAX_PATH, L'\0');
  for(;;) {
    const DWORD n = GetModuleFileNameW(nullptr, self.data(), static_cast<DWORD>(self.size()));
    if(n < self.size()) {
      self.resize(n);
      break;
    }
    self.resize(self.size() * 2);
  }
  const std::size_t slash = self.find_last_of(L"\\/");
  return (slash == std::wstring::npos ? std::wstring() : self.substr(0, slash + 1)) + L"lowkey.exe";
}

heap::cli::Invocation classifyArgs() {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::vector<std::wstring_view> args;
  for(int i = 1; argv != nullptr && i < argc; ++i) {
    args.emplace_back(argv[i]);
  }
  const heap::cli::Invocation kind = heap::cli::classify<wchar_t>(args);
  LocalFree(static_cast<void*>(argv));
  return kind;
}

// Runs heap.exe with the same arguments. A command shares this console and is
// waited for; a window launch is left to run.
int runHeap(bool command) {
  const std::wstring exe = heapExePath();
  std::wstring cmdLine = L"\"" + exe + L"\"";
  const std::wstring tail = argumentTail();
  if(!tail.empty()) {
    cmdLine += L" " + tail;
  }
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  if(command) {
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  }
  PROCESS_INFORMATION pi{};
  if(CreateProcessW(exe.c_str(), cmdLine.data(), nullptr, nullptr, command ? TRUE : FALSE, 0, nullptr, nullptr, &si, &pi) == 0) {
    heap::cli::write(true,
                     QStringLiteral("lowkey-cli: cannot start %1 (it belongs next to lowkey-cli.exe)\n").arg(QString::fromStdWString(exe)));
    return heap::cli::kExitData;
  }
  CloseHandle(pi.hThread);
  DWORD code = 0;
  if(command) {
    WaitForSingleObject(pi.hProcess, INFINITE);
    GetExitCodeProcess(pi.hProcess, &code);
  } else {
    // The window may come forward: the user just ran this.
    AllowSetForegroundWindow(pi.dwProcessId);
  }
  CloseHandle(pi.hProcess);
  return static_cast<int>(code);
}

}  // namespace

int main(int argc, char** argv) {
  if(classifyArgs() == heap::cli::Invocation::Window) {
    return runHeap(/*command=*/false);
  }
  qInstallMessageHandler(heap::cli::quietMessages);
  const QCoreApplication app(argc, argv);
  heap::cli::setApplicationIdentity();

  const heap::cli::ParsedArgs parsed = heap::cli::parseArgs(QCoreApplication::arguments().mid(1));
  if(!parsed.ok) {
    return heap::cli::usage(parsed.error);
  }
  heap::paths::setDataDir(parsed.dataDirSet ? parsed.dataDir : qEnvironmentVariable("HEAP_DATA_DIR"));
  if(const std::optional<int> answered = heap::cli::runQuery(parsed.request)) {
    return *answered;
  }
  // add, done, open: the AppController lives in heap.exe.
  AllowSetForegroundWindow(ASFW_ANY);
  return runHeap(/*command=*/true);
}
