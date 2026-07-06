#include "Logger.h"

#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStringList>

#include <csignal>

#ifdef Q_OS_MACOS
#include "platform/MacWindow.h"

#include <QQuickWindow>
#endif

// Injected by CMake from project() VERSION; fallback keeps ad-hoc builds sane.
#ifndef HEAP_VERSION
#define HEAP_VERSION "0.0.0-dev"
#endif

namespace {
void quitOnSignal(int) {
  QCoreApplication::quit();
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

  // Route qDebug/qWarning/… to a rotating log file (must come after the
  // org/app names are set so AppDataLocation resolves to the heap folder).
  heap::logging::installFileLogger();
  qInfo("heap %s starting", qUtf8Printable(app.applicationVersion()));

  QQuickStyle::setStyle("Basic");

  std::signal(SIGINT, quitOnSignal);
  std::signal(SIGTERM, quitOnSignal);

  QString initialView;
  const QStringList args = QApplication::arguments();
  for(int i = 1; i < args.size() - 1; ++i) {
    if(args[i] == "--view") {
      initialView = args[i + 1];
      break;
    }
  }

  QQmlApplicationEngine engine;
  engine.rootContext()->setContextProperty("INITIAL_VIEW", initialView);
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

  return QApplication::exec();
}
