// Qt Quick Test entry point for the QML-side unit tests.
//
// QUICK_TEST_MAIN_WITH_SETUP loads every tst_*.qml under the directory passed
// via the QUICK_TEST_SOURCE_DIR compile definition (see tests/CMakeLists.txt)
// and runs each TestCase. Runs headless under the offscreen QPA platform.
//
// The Setup object enables QStandardPaths test mode before any test loads, so
// component tests that construct AppController (which reads/seeds state.json
// under AppDataLocation) never touch the real user data.
#include <QObject>
#include <QStandardPaths>
#include <QtPlugin>
#include <QtQuickTest/quicktest.h>

// Explicitly instantiate the statically-linked TodoCpp module plugin so its
// type registrations run. Auto-registration happens to work on Windows but is
// stripped on Linux (the test references no plugin symbol otherwise), leaving
// "SideRail is not a type" at runtime. Q_IMPORT_PLUGIN forces the static plugin
// instance in; heap_core is WHOLE_ARCHIVE-linked so the module's qml resources
// (qmldir + component .qml) are retained alongside it.
Q_IMPORT_PLUGIN(TodoCppPlugin)

class Setup : public QObject {
  Q_OBJECT
 public slots:

  void applicationAvailable() {
    QStandardPaths::setTestModeEnabled(true);
  }
};

QUICK_TEST_MAIN_WITH_SETUP(heap_qml, Setup)

#include "quick_test_main.moc"
