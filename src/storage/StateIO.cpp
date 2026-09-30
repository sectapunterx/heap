#include "storage/StateIO.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QSaveFile>
#include <QTemporaryFile>
#include <QThread>

namespace heap::storage {

namespace {

Reader& readerSeam() {
  static Reader reader;
  return reader;
}

ReadResult readOnce(const QString& path) {
  ReadResult r;
  QFile f(path);
  if(!f.exists()) {
    r.kind = ReadResult::Missing;
    return r;
  }
  if(!f.open(QIODevice::ReadOnly)) {
    r.kind = ReadResult::Unreadable;
    r.error = f.errorString();
    return r;
  }
  r.bytes = f.readAll();
  if(f.error() != QFileDevice::NoError) {
    r.kind = ReadResult::Unreadable;
    r.error = f.errorString();
    r.bytes.clear();
    return r;
  }
  r.kind = ReadResult::Ok;
  return r;
}

}  // namespace

void setReaderForTesting(Reader reader) {
  readerSeam() = std::move(reader);
}

ReadResult readWithRetry(const QString& path, const QList<int>& backoffMs) {
  const Reader& seam = readerSeam();
  ReadResult r;
  for(int attempt = 0;; ++attempt) {
    r = seam ? seam(path) : readOnce(path);
    r.attempts = attempt + 1;
    if(r.kind != ReadResult::Unreadable || attempt >= backoffMs.size()) {
      return r;
    }
    QThread::msleep(static_cast<unsigned long>(backoffMs.at(attempt)));
  }
}

QList<int> startupBackoff() {
  return {100, 250, 500, 1000};
}

bool validateShape(const QJsonObject& root, QString* reason) {
  const auto fail = [reason](const QString& why) {
    if(reason) {
      *reason = why;
    }
    return false;
  };
  const QJsonValue version = root.value(QStringLiteral("schemaVersion"));
  if(!version.isUndefined() && !version.isDouble()) {
    return fail(QStringLiteral("schemaVersion is not a number"));
  }
  const int schema = version.toInt(1);
  const QJsonValue profiles = root.value(QStringLiteral("profiles"));
  if(schema >= 2 || !profiles.isUndefined()) {
    if(!profiles.isArray()) {
      return fail(profiles.isUndefined() ? QStringLiteral("no profiles array") : QStringLiteral("profiles is not an array"));
    }
    int objects = 0;
    for(const QJsonValue& v : profiles.toArray()) {
      objects += v.isObject() ? 1 : 0;
    }
    if(objects == 0) {
      return fail(QStringLiteral("profiles holds no profile"));
    }
    return true;
  }
  // Schema v1: flat collections at the root. An object with none of them is
  // not an old state file, it is an empty (or foreign) one.
  static const char* const kFlat[] = {"tasks", "statuses", "people", "events"};
  for(const char* key : kFlat) {
    if(root.value(QLatin1String(key)).isArray()) {
      return true;
    }
  }
  return fail(QStringLiteral("no profiles and no v1 collections"));
}

bool writeAtomically(const QString& path, const QByteArray& bytes, QString* error) {
  QSaveFile f(path);
  if(!f.open(QIODevice::WriteOnly)) {
    if(error) {
      *error = f.errorString();
    }
    return false;
  }
  if(f.write(bytes) != bytes.size()) {
    if(error) {
      *error = f.errorString();
    }
    f.cancelWriting();
    return false;
  }
  if(!f.commit()) {
    if(error) {
      *error = f.errorString();
    }
    return false;
  }
  return true;
}

bool probeWritableDir(const QString& dir, QString* error) {
  if(!QDir().mkpath(dir)) {
    if(error) {
      *error = QStringLiteral("cannot create %1").arg(QDir::toNativeSeparators(dir));
    }
    return false;
  }
  QTemporaryFile probe(dir + QStringLiteral("/.heap-write-probe-XXXXXX"));
  if(!probe.open()) {
    if(error) {
      *error = QStringLiteral("cannot write to %1: %2").arg(QDir::toNativeSeparators(dir), probe.errorString());
    }
    return false;
  }
  return true;
}

}  // namespace heap::storage
