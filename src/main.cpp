#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStringList>

#include <csignal>

namespace {
void quitOnSignal(int) { QCoreApplication::quit(); }
}

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    app.setOrganizationName("todocpp");
    app.setOrganizationDomain("todocpp.local");
    app.setApplicationName("todo-cpp");
    app.setApplicationDisplayName(QStringLiteral("todo·cpp"));

    QQuickStyle::setStyle("Basic");

    std::signal(SIGINT,  quitOnSignal);
    std::signal(SIGTERM, quitOnSignal);

    QString initialView;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size() - 1; ++i) {
        if (args[i] == "--view") { initialView = args[i + 1]; break; }
    }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("INITIAL_VIEW", initialView);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/TodoCpp/qml/Main.qml")));
    return app.exec();
}
