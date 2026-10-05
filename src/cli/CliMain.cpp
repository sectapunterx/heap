#include "AppController.h"
#include "Logger.h"

#include "cli/CliConsole.h"
#include "cli/CliCore.h"
#include "cli/CliExecutor.h"
#include "cli/CliMain.h"
#include "cli/CliQuery.h"
#include "cli/VerbScan.h"
#include "platform/Paths.h"
#include "platform/SingleInstance.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDeadlineTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QThread>

#include <optional>
#include <string_view>
#include <vector>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace heap::cli {

namespace {

// How long a change waits for the data dir: covers a window that holds it but
// is still starting up (its socket not listening yet).
constexpr int kWindowWaitMs = 4000;

Response headless(const Request& request) {
  // The same models and save path as the window, minus everything that
  // reaches outside the data dir (see AppController::setHeadless). The log
  // goes to heap.log only: the quiet handler installed first drops the echo.
  heap::logging::installFileLogger();
  qInfo("command line: %s", request.verb == Verb::Add ? "add" : "done");
  AppController::setHeadless(true);
  Response r;
  {
    AppController controller;
    if(controller.storageState() != QLatin1String("ok")) {
      r.exitCode = kExitData;
      r.err = QStringLiteral("heap: nothing changed: %1\n").arg(controller.storageMessage());
    } else {
      r = execute(controller, request, QDateTime::currentDateTime());
      controller.flushSave();
      if(controller.storageState() != QLatin1String("ok")) {
        r.exitCode = kExitData;
        r.err += QStringLiteral("heap: the change was not saved: %1\n").arg(controller.storageMessage());
      }
    }
  }
  heap::logging::closeFileLogger();
  return r;
}

// `heap open` with no window: start one on that task, detached, so the shell
// gets its prompt back.
Response launchOnTask(const Request& request, bool dataDirSet) {
  QString error;
  const std::optional<Snapshot> s = readSnapshot(&error);
  if(!s) {
    return {kExitData, QString(), QStringLiteral("heap: %1\n").arg(error)};
  }
  const TaskRef ref = findTask(*s, request.taskId, findProfile(*s, QString()));
  if(!ref.found()) {
    return {kExitNotFound, QString(), QStringLiteral("heap: no task '%1'\n").arg(request.taskId)};
  }
  const QString id = s->profiles.at(ref.profile).tasks.at(ref.task).id;
  QStringList args;
  if(dataDirSet) {
    args << QStringLiteral("--data-dir") << heap::paths::dataDir();
  }
  args << QStringLiteral("--") + QLatin1String(kOpenTaskOption) << id;
  // Not on this console's handles: a window holding them would keep a pipe
  // open (`heap open X | cat` would never end) and write into the shell.
#ifdef Q_OS_WIN
  // startDetached hands the null device over by inheritance, which passes on
  // every inheritable handle — this console's, too (heap-cli gave them to us
  // inheritable).
  for(const DWORD which : {STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE}) {
    HANDLE h = GetStdHandle(which);
    if(h != nullptr && h != INVALID_HANDLE_VALUE) {
      SetHandleInformation(h, HANDLE_FLAG_INHERIT, 0);
    }
  }
#endif
  QProcess window;
  window.setProgram(QCoreApplication::applicationFilePath());
  window.setArguments(args);
  window.setStandardInputFile(QProcess::nullDevice());
  window.setStandardOutputFile(QProcess::nullDevice());
  window.setStandardErrorFile(QProcess::nullDevice());
  if(!window.startDetached()) {
    return {kExitData, QString(), QStringLiteral("heap: could not start heap\n")};
  }
  Response r;
  r.out = request.json
              ? QString::fromUtf8(QJsonDocument(QJsonObject{{QStringLiteral("id"), id}}).toJson(QJsonDocument::Compact)) + QChar('\n')
              : QStringLiteral("Opening %1\n").arg(id);
  return r;
}

}  // namespace

bool isCommandLine(int argc, char** argv) {
  std::vector<std::string_view> args;
  for(int i = 1; i < argc; ++i) {
    args.emplace_back(argv[i]);
  }
  return classify<char>(args) == Invocation::Command;
}

int run(int argc, char** argv) {
  attachConsole();
  qInstallMessageHandler(quietMessages);

  const QCoreApplication app(argc, argv);
  setApplicationIdentity();

  const ParsedArgs parsed = parseArgs(QCoreApplication::arguments().mid(1));
  if(!parsed.ok) {
    return usage(parsed.error);
  }
  const Request& request = parsed.request;
  heap::paths::setDataDir(parsed.dataDirSet ? parsed.dataDir : qEnvironmentVariable("HEAP_DATA_DIR"));

  if(const std::optional<int> answered = runQuery(request)) {
    return *answered;
  }

#ifdef Q_OS_WIN
  if(request.verb == Verb::Open) {
    // The window may only take the foreground if the process the user just
    // ran (which owns it) lets it.
    AllowSetForegroundWindow(ASFW_ANY);
  }
#endif

  // Changes go through the window when it is open; otherwise this process
  // holds the data dir (a window started meanwhile waits for it) and applies
  // them itself.
  const QByteArray line = encodeRequest(request);
  const QDeadlineTimer deadline(kWindowWaitMs);
  for(;;) {
    if(const std::optional<Response> r = askWindow(line)) {
      return report(*r);
    }
    if(request.verb == Verb::Open) {
      // The window about to start takes the lock itself: only look, then let go.
      bool free = false;
      {
        heap::platform::SingleInstance probe(heap::paths::dataDir());
        free = probe.tryLock();
      }
      if(free) {
        return report(launchOnTask(request, parsed.dataDirSet));
      }
    } else {
      heap::platform::SingleInstance owner(heap::paths::dataDir());
      if(owner.tryLock()) {
        return report(headless(request));
      }
    }
    if(deadline.hasExpired()) {
      return report({kExitData, QString(), QStringLiteral("heap: another heap is using this data directory and is not responding\n")});
    }
    QThread::msleep(100);
  }
}

}  // namespace heap::cli
