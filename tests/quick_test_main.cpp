// Qt Quick Test entry point for the QML-side unit tests.
//
// QUICK_TEST_MAIN loads every tst_*.qml under the directory passed via
// `-input <dir>` (wired in tests/CMakeLists.txt) and runs each TestCase.
// Runs headless under the offscreen QPA platform in CI.
#include <QtQuickTest/quicktest.h>

QUICK_TEST_MAIN(heap_qml)
