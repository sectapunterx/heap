#include "AppController.h"
#include "Logger.h"
#include "ViewNames.h"

#include "cli/CliCore.h"
#include "cli/CliExecutor.h"
#include "cli/CliMain.h"
#include "diag/PerfLog.h"
#include "notify/NotificationCenter.h"
#include "notify/NotifyPayload.h"
#include "platform/AltGrGuard.h"
#include "platform/Paths.h"
#include "platform/SingleInstance.h"
#include "platform/Sound.h"
#include "storage/StateIO.h"

#include <QApplication>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QIcon>
#include <QImageReader>
#include <QMessageBox>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStringList>
#include <QTemporaryDir>
#include <QTimer>

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <optional>

#ifdef Q_OS_MACOS
#include "platform/MacWindow.h"
#endif

// Injected by CMake from project() VERSION; fallback keeps ad-hoc builds sane.
#ifndef HEAP_VERSION
#define HEAP_VERSION "0.0.0-dev"
#endif

namespace {
void quitOnSignal(int) {
  QCoreApplication::quit();
}

// Parsed command line. `--data-dir` is applied before anything resolves a path,
// so a throwaway run can be pointed away from the real profile.
struct CliOptions {
  QString initialView;
  QString dataDir;
  bool dataDirSet = false;
  bool smoke = false;
  bool capture = false;
  // Started by the login entry (APP-154): come up hidden in the tray.
  bool minimized = false;
  // A notification click (APP-155): the shell starts heap with the toast's
  // heap://notify URI as the only argument.
  QString notifyUri;
  QString openTask;  // `heap open <id>` started this window on that task
  bool perfLog = false;
};

// Exit code for a command line heap cannot act on — the same "usage" code the
// command-line verbs use (heap::cli::kExitUsage).
constexpr int kUsageExit = heap::cli::kExitUsage;

// How long --smoke lets the UI settle before judging it: long enough for the
// deferred loaders and the first frame, short enough for a CI step.
constexpr int kSmokeSettleMs = 2000;

[[noreturn]] void usageError(const QCommandLineParser& parser, const QString& message) {
  fputs(qPrintable(QStringLiteral("heap: %1\n\n").arg(message) + parser.helpText()), stderr);
  std::exit(kUsageExit);
}

// Parses heap's own options. Qt's own switches (-platform, -style, ...) are
// consumed by QApplication before this sees the list. Anything else heap does
// not know is an error with the usage text and a non-zero exit (REL-2): a
// typo'd flag that silently started the GUI looked as if it had worked.
// --help and --version exit here.
CliOptions parseCommandLine(const QStringList& args) {
  QCommandLineParser parser;
  // ASCII only: this is printed straight to a console whose code page is not
  // guaranteed to be UTF-8 (cp866/cp1251 on a stock Windows shell).
  parser.setApplicationDescription(QStringLiteral("heap - keyboard-first tickets, planning and notes for engineers."));
  const QCommandLineOption helpOption = parser.addHelpOption();
  const QCommandLineOption versionOption = parser.addVersionOption();

  const QCommandLineOption viewOption(
      QStringLiteral("view"),
      QStringLiteral("Open <name> instead of the last used view: %1.").arg(heap::views::all().join(QStringLiteral(", "))),
      QStringLiteral("name"));
  parser.addOption(viewOption);

  const QCommandLineOption dataDirOption(QStringLiteral("data-dir"),
                                         QStringLiteral("Keep state.json, backups, logs and secrets in <dir> instead of the "
                                                        "platform default. Also settable with HEAP_DATA_DIR."),
                                         QStringLiteral("dir"));
  parser.addOption(dataDirOption);

  const QCommandLineOption smokeOption(
      QStringLiteral("smoke"),
      QStringLiteral("Load the whole UI against a throwaway profile (a copy of --data-dir's state.json, if given), "
                     "report any QML error, missing plugin or image format on stderr, and exit: 0 when healthy. "
                     "With --data-dir the run's log is kept as <dir>/logs/smoke.log. Used to check a packaged build."));
  parser.addOption(smokeOption);

  // Bindable from the desktop's own keyboard settings where heap cannot grab
  // a global key itself (Wayland without the shortcuts portal, APP-171).
  const QCommandLineOption captureOption(QStringLiteral("capture"),
                                         QStringLiteral("Open quick capture - in the heap already running for this data "
                                                        "directory, or in a new one."));
  parser.addOption(captureOption);
  const QCommandLineOption minimizedOption(
      QStringLiteral("minimized"),
      QStringLiteral("Start hidden in the tray (minimized where there is no tray), and leave an already "
                     "running heap where it is. The start-at-login entry passes it."));
  parser.addOption(minimizedOption);
  QCommandLineOption openTaskOption(QString::fromLatin1(heap::cli::kOpenTaskOption), QString(), QStringLiteral("id"));
  openTaskOption.setFlags(QCommandLineOption::HiddenFromHelp);
  parser.addOption(openTaskOption);
  const QCommandLineOption perfLogOption(QStringLiteral("perf-log"),
                                         QStringLiteral("Log startup and capture timings to the log (perf: ... lines). "
                                                        "Also settable with HEAP_PERF_LOG=1."));
  parser.addOption(perfLogOption);

  // A macOS Finder launch may still append -psn_<n>_<m>; it is not the user's.
  QStringList filtered;
  for(const QString& a : args) {
    if(!a.startsWith(QLatin1String("-psn_"))) {
      filtered << a;
    }
  }
  const bool parsed = parser.parse(filtered);

  // showHelp/showVersion terminate the process, so these come after parsing.
  if(parser.isSet(helpOption)) {
    parser.showHelp(0);
  }
  if(parser.isSet(versionOption)) {
    parser.showVersion();
  }
  if(!parsed) {
    usageError(parser, parser.errorText());
  }
  // heap takes no positional arguments but a notification click's URI (the
  // verbs are answered before this parser runs). A path left over from a
  // forgotten `--data-dir` used to be ignored and the GUI opened — and
  // migrated — the real profile instead of the folder meant (PLAT-1).
  QStringList positional = parser.positionalArguments();
  CliOptions opts;
  if(positional.size() == 1 && heap::notify::isNotifyUri(positional.constFirst())) {
    opts.notifyUri = positional.takeFirst().trimmed();
  }
  if(!positional.isEmpty()) {
    usageError(parser,
               QStringLiteral("unexpected argument '%1' (commands: add, now, list, today, done, open, help)").arg(positional.constFirst()));
  }

  opts.initialView = parser.value(viewOption);
  opts.dataDirSet = parser.isSet(dataDirOption);
  opts.dataDir = parser.value(dataDirOption);
  opts.smoke = parser.isSet(smokeOption);
  opts.capture = parser.isSet(captureOption);
  opts.minimized = parser.isSet(minimizedOption);
  opts.openTask = parser.value(openTaskOption).trimmed();
  opts.perfLog = parser.isSet(perfLogOption);
  if(parser.isSet(viewOption) && !heap::views::isKnown(opts.initialView)) {
    usageError(parser,
               QStringLiteral("unknown view '%1' (valid: %2)").arg(opts.initialView, heap::views::all().join(QStringLiteral(", "))));
  }
  // `--data-dir ""` (an unset shell variable) must never mean "the real
  // profile" — keeping a run away from it is what the flag is for (PLAT-22).
  if(opts.dataDirSet && opts.dataDir.trimmed().isEmpty()) {
    usageError(parser, QStringLiteral("--data-dir needs a directory"));
  }
  return opts;
}

// Judges a --smoke run once the UI has settled. Each line goes to the log and
// straight to stderr: the logger hands messages on to Qt's own handler, which
// in a Windows GUI-subsystem build is OutputDebugString, so a redirected
// stderr stayed empty (PLAT-2). The run's whole log is also kept next to the
// profile it was given — see LogCloser.
int smokeVerdict(const QQmlApplicationEngine& engine, const QList<QQmlError>& qmlWarnings) {
  QStringList problems;

  const QList<QObject*> roots = engine.rootObjects();
  if(roots.isEmpty() || qobject_cast<QQuickWindow*>(roots.constFirst()) == nullptr) {
    problems << QStringLiteral("Main.qml did not create a window");
  }
  for(const QQmlError& warning : qmlWarnings) {
    problems << QStringLiteral("QML: ") + warning.toString();
  }
  // The brand icons and logos are SVG; a bundle without the qsvg plugin (the
  // v0.4.3 Windows zip) starts fine and quietly shows no icons.
  if(!QImageReader::supportedImageFormats().contains("svg")) {
    problems << QStringLiteral("no svg image format plugin");
  }
  if(QApplication::windowIcon().pixmap(32, 32).isNull()) {
    problems << QStringLiteral("window icon did not render");
  }

  for(const QString& problem : problems) {
    qCritical("smoke: %s", qUtf8Printable(problem));
    static_cast<void>(fprintf(stderr, "smoke: %s\n", qUtf8Printable(problem)));
  }
  const QString verdict = QStringLiteral("smoke: %1 (%2 problem(s))")
                              .arg(problems.isEmpty() ? QStringLiteral("OK") : QStringLiteral("FAILED"))
                              .arg(problems.size());
  qInfo("%s", qUtf8Printable(verdict));
  static_cast<void>(fprintf(stderr, "%s\n", qUtf8Printable(verdict)));
  static_cast<void>(fflush(stderr));
  return problems.isEmpty() ? 0 : 1;
}

// Closes heap.log when it goes out of scope. Declared between the smoke temp
// dir and the QML engine, so it runs after the engine (and AppController's
// final save) and before the temp dir is removed: an open log is what used to
// keep every --smoke run's %TEMP%\heap-XXXXXX behind (PLAT-16).
//
// With --data-dir, the closed log is first copied to <dir>/logs/smoke.log:
// the temp folder goes, and with it the only record of *why* a packaged build
// failed its smoke test (PLAT-2). The profile's own heap.log is not touched.
struct LogCloser {
  bool enabled = false;
  QString keepAs;  // where the smoke run's log is copied; empty = nowhere

  ~LogCloser() {
    if(!enabled) {
      return;
    }
    heap::logging::closeFileLogger();
    if(!keepAs.isEmpty() && QDir().mkpath(QFileInfo(keepAs).absolutePath())) {
      QFile::remove(keepAs);
      if(!QFile::copy(heap::logging::logFilePath(), keepAs)) {
        static_cast<void>(fprintf(stderr, "heap: could not keep the smoke log as %s\n", qUtf8Printable(keepAs)));
      }
    }
  }
};
}  // namespace

int main(int argc, char* argv[]) {
  // `heap add …`, `heap now`, --help: answered on the console, no window and
  // no GUI application object (APP-173).
  if(heap::cli::isCommandLine(argc, argv)) {
    return heap::cli::run(argc, argv);
  }

  heap::perf::markProcessStart();
  QApplication app(argc, argv);
  QApplication::setOrganizationName("heap");
  QApplication::setOrganizationDomain("heap.local");
  QApplication::setApplicationName("heap");
  QApplication::setApplicationDisplayName(QStringLiteral("heap."));
  QApplication::setApplicationVersion(QStringLiteral(HEAP_VERSION));
  QApplication::setWindowIcon(QIcon(QStringLiteral(":/brand/icon/heap-icon.svg")));

  const CliOptions cli = parseCommandLine(QApplication::arguments());
  if(cli.perfLog) {
    heap::perf::setEnabled(true);
  }

  // AltGr+E in a text field types €, not "new event" (SHELL-2).
  heap::platform::AltGrGuard altGrGuard;
  QApplication::instance()->installEventFilter(&altGrGuard);

  // Redirect the data directory before the logger opens its file and before
  // AppController resolves state.json. The flag wins over the environment so a
  // single run can override a shell-wide HEAP_DATA_DIR. --smoke never touches a
  // real profile: it always runs in a temporary one, removed on exit. With
  // --data-dir, that profile's state.json is copied in first, so the smoke
  // test loads real data without migrating or rewriting it (PLAT-16).
  const QTemporaryDir smokeDataDir;
  QString dataDir = cli.dataDirSet ? cli.dataDir : qEnvironmentVariable("HEAP_DATA_DIR");
  QString smokeLogKeep;

  // A notification click from a throwaway profile names its folder. Only a
  // heap already running there is told; nothing is started or written in a
  // folder that came from a URI (APP-155).
  const heap::notify::NotifyUri clicked = heap::notify::parseNotifyUri(cli.notifyUri);
  if(!cli.notifyUri.isEmpty() && !clicked.ok) {
    return kUsageExit;
  }
  if(clicked.ok && !clicked.dataDir.isEmpty() && !cli.dataDirSet) {
    heap::platform::SingleInstance::forwardOnly(clicked.dataDir, "notify " + cli.notifyUri.toUtf8());
    return 0;
  }
  if(cli.smoke) {
    heap::platform::setSoundSuppressed(true);
    const QString source = dataDir;
    if(!source.isEmpty()) {
      smokeLogKeep = QDir(source).filePath(QStringLiteral("logs/smoke.log"));
    }
    dataDir = smokeDataDir.path();
    if(!source.isEmpty()) {
      QFile::copy(QDir(source).filePath(QStringLiteral("state.json")), QDir(dataDir).filePath(QStringLiteral("state.json")));
    }
  }
  heap::paths::setDataDir(dataDir);

  // Say it on the console too: a GUI that cannot save is otherwise only a
  // banner, and nobody scripting heap reads that (PLAT-4).
  {
    QString why;
    if(!heap::storage::probeWritableDir(heap::paths::dataDir(), &why)) {
      fputs(qPrintable(QStringLiteral("heap: data directory is not writable, nothing will be saved: %1\n").arg(why)), stderr);
    }
  }

  // One heap per data directory (PLAT-2): a second launch brings the running
  // window forward (switching view if --view was given) and exits.
  heap::platform::SingleInstance instance(heap::paths::dataDir());
  if(!cli.smoke) {
    // A login start that finds heap already running leaves its window alone;
    // a notification click is the running heap's to act on.
    QByteArray hello = cli.capture ? QByteArrayLiteral("capture") : cli.minimized ? QByteArray("ping") : QByteArray("activate");
    if(clicked.ok) {
      hello = "notify " + cli.notifyUri.toUtf8();
    } else if(!cli.minimized && !cli.initialView.isEmpty()) {
      hello += " view=" + cli.initialView.toUtf8();
    }
    switch(instance.acquire(hello)) {
      case heap::platform::SingleInstance::Result::Primary:
        break;
      case heap::platform::SingleInstance::Result::Forwarded:
        return 0;
      case heap::platform::SingleInstance::Result::Busy:
        fputs("heap: another heap is using this data directory and is not responding\n", stderr);
        QMessageBox::warning(nullptr,
                             QStringLiteral("heap"),
                             QStringLiteral("heap is already running with this data folder, but it is not responding:\n%1\n\n"
                                            "Close it (or end it in the task manager) and start heap again.")
                                 .arg(QDir::toNativeSeparators(heap::paths::dataDir())));
        return 1;
    }
  }

  // Route qDebug/qWarning/… to a rotating log file (must come after the
  // org/app names are set so AppDataLocation resolves to the heap folder).
  heap::logging::installFileLogger();
  LogCloser logCloser{cli.smoke, smokeLogKeep};
  qInfo("heap %s starting", qUtf8Printable(app.applicationVersion()));
  if(heap::paths::dataDirOverridden()) {
    qInfo("data directory overridden: %s", qUtf8Printable(heap::paths::dataDir()));
  }

  QQuickStyle::setStyle("Basic");

  // A health check leaves the OS alone: no AppUserModelID, no heap:// handler.
  if(cli.smoke) {
    heap::notify::NotificationCenter::setNativeAllowed(false);
  }

  std::signal(SIGINT, quitOnSignal);
  std::signal(SIGTERM, quitOnSignal);

  QQmlApplicationEngine engine;
  engine.rootContext()->setContextProperty("INITIAL_VIEW", cli.initialView);
  // A snooze clicked while heap was closed starts it in the tray: the click
  // asked for the reminder later, not for the window.
  const bool clickWantsWindow = !clicked.ok || clicked.actionId == QLatin1String(heap::notify::kDefaultAction) ||
                                clicked.actionId == QLatin1String(heap::notify::kOpen);
  engine.rootContext()->setContextProperty("START_MINIMIZED", (cli.minimized || !clickWantsWindow) && !cli.smoke);
  QList<QQmlError> smokeWarnings;
  if(cli.smoke) {
    QObject::connect(&engine, &QQmlEngine::warnings, &app, [&smokeWarnings](const QList<QQmlError>& warnings) {
      smokeWarnings += warnings;
    });
  }
  QObject::connect(
      &engine,
      &QQmlApplicationEngine::objectCreationFailed,
      &app,
      []() {
        QCoreApplication::exit(-1);
      },
      Qt::QueuedConnection);
  engine.load(QUrl(QStringLiteral("qrc:/qt/qml/TodoCpp/qml/Main.qml")));
  heap::perf::log(QStringLiteral("startup qml-loaded"), heap::perf::sinceProcessStart());

  // The first frame the main window presents, measured from main() (APP-161).
  // frameSwapped may come from the render thread; logging there is safe.
  if(heap::perf::enabled() && !engine.rootObjects().isEmpty()) {
    if(auto* win = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst())) {
      QObject::connect(
          win,
          &QQuickWindow::frameSwapped,
          win,
          []() {
            heap::perf::log(QStringLiteral("startup first-frame"), heap::perf::sinceProcessStart());
          },
          static_cast<Qt::ConnectionType>(Qt::DirectConnection | Qt::SingleShotConnection));
    }
  }

#ifdef Q_OS_MACOS
  // Unify the title bar with the app's top strip (traffic lights inlaid).
  if(!engine.rootObjects().isEmpty()) {
    if(auto* win = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst())) {
      heap::platform::applyUnifiedTitlebar(win);
    }
  }
#endif

  // A second launch forwarded here: bring the window forward, the same way
  // the tray's "Show" does (it also restores a window hidden to the tray).
  QObject::connect(&instance, &heap::platform::SingleInstance::messageReceived, &app, [&engine](const QByteArray& message) {
    const QList<QObject*> roots = engine.rootObjects();
    if(roots.isEmpty() || message == "ping") {
      return;
    }
    // A notification click: the controller decides whether the window comes
    // forward (Open does, a snooze does not).
    if(message.startsWith("notify ")) {
      if(auto* controller = engine.singletonInstance<AppController*>("TodoCpp", "AppController")) {
        controller->handleNotificationUri(QString::fromUtf8(message.mid(7)));
      }
      return;
    }
    // `heap --capture` from a desktop shortcut: the capture popup, the way
    // the global hotkey opens it, without raising the whole window.
    if(message.startsWith("capture")) {
      if(auto* controller = engine.singletonInstance<AppController*>("TodoCpp", "AppController")) {
        emit controller->quickCaptureRequested();
      }
      return;
    }
    const qsizetype at = message.indexOf("view=");
    if(at >= 0) {
      if(auto* controller = engine.singletonInstance<AppController*>("TodoCpp", "AppController")) {
        controller->setCurrentView(QString::fromUtf8(message.mid(at + 5)).trimmed());
      }
    }
    QMetaObject::invokeMethod(roots.constFirst(), "_summon");
  });

  // Started by a notification click: act on it once the UI is up.
  if(clicked.ok && !cli.smoke) {
    QTimer::singleShot(0, &app, [&engine, uri = cli.notifyUri]() {
      if(auto* controller = engine.singletonInstance<AppController*>("TodoCpp", "AppController")) {
        controller->handleNotificationUri(uri);
      }
    });
  }

  // `heap add|done|now|…` run while this window is open (APP-173): applied to
  // the live models, so the change shows at once, undoes and saves as any
  // other. Set before exec(), so no request can arrive ahead of it.
  instance.setRequestHandler([&engine](const QByteArray& line) -> QByteArray {
    const std::optional<heap::cli::Request> request = heap::cli::decodeRequest(line);
    if(!request) {
      return heap::cli::encodeResponse(
          {heap::cli::kExitUsage, QString(), QStringLiteral("heap: the window did not understand the request\n")});
    }
    auto* controller = engine.singletonInstance<AppController*>("TodoCpp", "AppController");
    if(controller == nullptr) {
      return heap::cli::encodeResponse({heap::cli::kExitData, QString(), QStringLiteral("heap: the window is not ready\n")});
    }
    return heap::cli::encodeResponse(heap::cli::execute(*controller, *request, QDateTime::currentDateTime()));
  });

  // Started by `heap open <id>` with no window open: show that task.
  if(!cli.openTask.isEmpty()) {
    QTimer::singleShot(0, &app, [&engine, id = cli.openTask]() {
      if(auto* controller = engine.singletonInstance<AppController*>("TodoCpp", "AppController")) {
        heap::cli::Request request;
        request.verb = heap::cli::Verb::Open;
        request.taskId = id;
        heap::cli::execute(*controller, request, QDateTime::currentDateTime());
      }
    });
  }

  if(cli.smoke) {
    QTimer::singleShot(kSmokeSettleMs, &app, [&engine, &smokeWarnings]() {
      QCoreApplication::exit(smokeVerdict(engine, smokeWarnings));
    });
  }

  return QApplication::exec();
}
