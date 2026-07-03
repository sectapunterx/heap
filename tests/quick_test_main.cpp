// Qt Quick Test entry point for the QML-side unit tests.
//
// QUICK_TEST_MAIN_WITH_SETUP loads every tst_*.qml under the directory passed
// via the QUICK_TEST_SOURCE_DIR compile definition (see tests/CMakeLists.txt)
// and runs each TestCase. Runs headless under the offscreen QPA platform.
//
// The Setup object enables QStandardPaths test mode before any test loads, so
// component tests that construct AppController (which reads/seeds state.json
// under AppDataLocation) never touch the real user data.
#include <QtQuickTest/quicktest.h>

#include <QObject>
#include <QStandardPaths>

class Setup : public QObject {
  Q_OBJECT
 public slots:
  void applicationAvailable() {
    QStandardPaths::setTestModeEnabled(true);
  }
};

QUICK_TEST_MAIN_WITH_SETUP(heap_qml, Setup)

#include "quick_test_main.moc"
