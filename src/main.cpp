#include "Logger.h"

#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStringList>

#include <csignal>

namespace {
void quitOnSignal(int) {
  QCoreApplication::quit();
}
}  // namespace

int main(int argc, char* argv[]) {
  QApplication app(argc, argv);
  app.setOrganizationName("heap");
  app.setOrganizationDomain("heap.local");
  app.setApplicationName("heap");
  app.setApplicationDisplayName(QStringLiteral("heap."));
  app.setApplicationVersion(QStringLiteral("0.4.2"));
  app.setWindowIcon(QIcon(QStringLiteral(":/brand/icon/heap-icon.svg")));

  // Route qDebug/qWarning/… to a rotating log file (must come after the
  // org/app names are set so AppDataLocation resolves to the heap folder).
  heap::logging::installFileLogger();
  qInfo("heap %s starting", qUtf8Printable(app.applicationVersion()));

  QQuickStyle::setStyle("Basic");

  std::signal(SIGINT, quitOnSignal);
  std::signal(SIGTERM, quitOnSignal);

  QString initialView;
  const QStringList args = app.arguments();
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
  return app.exec();
}
