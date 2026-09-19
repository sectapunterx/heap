#include "platform/Paths.h"

#include <QDir>
#include <QStandardPaths>

namespace heap::paths {

namespace {
// Written once from main() before any other thread exists; read everywhere
// afterwards (including from the logger's message handler, which can run on a
// worker thread). A function-local static keeps the initialisation order
// well-defined no matter which translation unit asks first.
QString& overrideDir() {
  static QString dir;
  return dir;
}
}  // namespace

void setDataDir(const QString& dir) {
  if(dir.isEmpty()) {
    return;
  }
  overrideDir() = QDir(dir).absolutePath();
}

QString dataDir() {
  const QString& over = overrideDir();
  if(!over.isEmpty()) {
    return over;
  }
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

bool dataDirOverridden() {
  return !overrideDir().isEmpty();
}

}  // namespace heap::paths
