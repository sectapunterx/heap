#include "Logger.h"

#include "platform/Paths.h"

#include <QApplication>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QIcon>
#include <QImageReader>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStringList>
#include <QTemporaryDir>
#include <QTimer>

#include <csignal>

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
  bool smoke = false;
};

// How long --smoke lets the UI settle before judging it: long enough for the
// deferred loaders and the first frame, short enough for a CI step.
constexpr int kSmokeSettleMs = 2000;

// Parses heap's own options. Deliberately uses parse() rather than process():
// unknown arguments are reported and then ignored, so Qt's own platform
// switches (and anything a launcher appends) keep working as they did before
// heap had a parser at all. --help and --version exit here.
CliOptions parseCommandLine(const QStringList& args) {
  QCommandLineParser parser;
  // ASCII only: this is printed straight to a console whose code page is not
  // guaranteed to be UTF-8 (cp866/cp1251 on a stock Windows shell).
  parser.setApplicationDescription(QStringLiteral("heap - keyboard-first tickets, planning and notes for engineers."));
  const QCommandLineOption helpOption = parser.addHelpOption();
  const QCommandLineOption versionOption = parser.addVersionOption();

  const QCommandLineOption viewOption(QStringLiteral("view"),
                                      QStringLiteral("Open <name> instead of the last used view (kanban, week, notes, ...)."),
                                      QStringLiteral("name"));
  parser.addOption(viewOption);

  const QCommandLineOption dataDirOption(QStringLiteral("data-dir"),
                                         QStringLiteral("Keep state.json, backups, logs and secrets in <dir> instead of the "
                                                        "platform default. Also settable with HEAP_DATA_DIR."),
                                         QStringLiteral("dir"));
  parser.addOption(dataDirOption);

  const QCommandLineOption smokeOption(
      QStringLiteral("smoke"),
      QStringLiteral("Load the whole UI against a throwaway profile, report any QML error, missing plugin or "
                     "image format, and exit: 0 when healthy. Used to check a packaged build."));
  parser.addOption(smokeOption);

  if(!parser.parse(args)) {
    fputs(qPrintable(parser.errorText() + QLatin1Char('\n')), stderr);
  }
  for(const QString& unknown : parser.unknownOptionNames()) {
    fputs(qPrintable(QStringLiteral("heap: ignoring unknown option --%1\n").arg(unknown)), stderr);
  }

  // showHelp/showVersion terminate the process, so these come after parsing.
  if(parser.isSet(helpOption)) {
    parser.showHelp(0);
  }
  if(parser.isSet(versionOption)) {
    parser.showVersion();
  }

  CliOptions opts;
  opts.initialView = parser.value(viewOption);
  opts.dataDir = parser.value(dataDirOption);
  opts.smoke = parser.isSet(smokeOption);
  return opts;
}

// Judges a --smoke run once the UI has settled. Everything goes through the
// logger, so it reaches stderr and heap.log — the latter is what a CI step can
// read back from a Windows GUI-subsystem build, which has no console.
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
  }
  qInfo("smoke: %s (%lld problem(s))", problems.isEmpty() ? "OK" : "FAILED", static_cast<long long>(problems.size()));
  return problems.isEmpty() ? 0 : 1;
}
}  // namespace

int main(int argc, char* argv[]) {
  QApplication app(argc, argv);
  QApplication::setOrganizationName("heap");
  QApplication::setOrganizationDomain("heap.local");
  QApplication::setApplicationName("heap");
  QApplication::setApplicationDisplayName(QStringLiteral("heap."));
  QApplication::setApplicationVersion(QStringLiteral(HEAP_VERSION));
  QApplication::setWindowIcon(QIcon(QStringLiteral(":/brand/icon/heap-icon.svg")));

  const CliOptions cli = parseCommandLine(QApplication::arguments());

  // Redirect the data directory before the logger opens its file and before
  // AppController resolves state.json. The flag wins over the environment so a
  // single run can override a shell-wide HEAP_DATA_DIR. --smoke never touches a
  // real profile: without --data-dir it gets a temporary one, removed on exit.
  const QTemporaryDir smokeDataDir;
  QString dataDir = cli.dataDir.isEmpty() ? qEnvironmentVariable("HEAP_DATA_DIR") : cli.dataDir;
  if(cli.smoke && cli.dataDir.isEmpty()) {
    dataDir = smokeDataDir.path();
  }
  heap::paths::setDataDir(dataDir);

  // Route qDebug/qWarning/… to a rotating log file (must come after the
  // org/app names are set so AppDataLocation resolves to the heap folder).
  heap::logging::installFileLogger();
  qInfo("heap %s starting", qUtf8Printable(app.applicationVersion()));
  if(heap::paths::dataDirOverridden()) {
    qInfo("data directory overridden: %s", qUtf8Printable(heap::paths::dataDir()));
  }

  QQuickStyle::setStyle("Basic");

  std::signal(SIGINT, quitOnSignal);
  std::signal(SIGTERM, quitOnSignal);

  QQmlApplicationEngine engine;
  engine.rootContext()->setContextProperty("INITIAL_VIEW", cli.initialView);
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

#ifdef Q_OS_MACOS
  // Unify the title bar with the app's top strip (traffic lights inlaid).
  if(!engine.rootObjects().isEmpty()) {
    if(auto* win = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst())) {
      heap::platform::applyUnifiedTitlebar(win);
    }
  }
#endif

  if(cli.smoke) {
    QTimer::singleShot(kSmokeSettleMs, &app, [&engine, &smokeWarnings]() {
      QCoreApplication::exit(smokeVerdict(engine, smokeWarnings));
    });
  }

  return QApplication::exec();
}
