#include "platform/Brand.h"
#include "platform/LegacyData.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QLockFile>
#include <QSaveFile>

namespace heap::platform::legacy {

namespace {

const QString kState = QStringLiteral("state.json");

bool isLockFile(const QString& name) {
  return name.endsWith(QLatin1String(".lock")) || name.endsWith(QLatin1String(".lock.rmlock"));
}

// True while a heap of 0.7.x holds the old folder's lock: copying then could
// catch a state.json half-way through a save, and the old heap would go on
// writing to a folder nobody reads any more.
bool legacyRunning(const QString& legacyDir) {
  QLockFile lock(QDir(legacyDir).filePath(QLatin1String(heap::brand::kLegacyLockFile)));
  lock.setStaleLockTime(0);
  if(lock.tryLock(0)) {
    lock.unlock();
    return false;
  }
  return lock.error() == QLockFile::LockFailedError;
}

bool copyTree(const QString& from, const QString& to, int* files, QString* error) {
  QDirIterator it(from, QDir::Files | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
  const QDir src(from);
  while(it.hasNext()) {
    const QString path = it.next();
    const QString rel = src.relativeFilePath(path);
    if(isLockFile(QFileInfo(path).fileName()) || rel == QLatin1String(heap::brand::kMovedMarker)) {
      continue;
    }
    const QString target = QDir(to).filePath(rel);
    QDir().mkpath(QFileInfo(target).absolutePath());
    if(!QFile::copy(path, target)) {
      *error = QStringLiteral("could not copy %1").arg(QDir::toNativeSeparators(path));
      return false;
    }
    ++*files;
  }
  return true;
}

}  // namespace

QString legacyDirFor(const QString& newDir) {
  // By the string, not QDir::cdUp(): on a first launch the new folder does
  // not exist yet, and cdUp() refuses to leave a folder that is not there.
  QStringList parts = QDir::cleanPath(QDir(newDir).absolutePath()).split(QLatin1Char('/'));
  if(parts.size() < 3 || parts.at(parts.size() - 1).compare(QLatin1String(heap::brand::kName), Qt::CaseInsensitive) != 0 ||
     parts.at(parts.size() - 2).compare(QLatin1String(heap::brand::kName), Qt::CaseInsensitive) != 0) {
    return {};
  }
  parts[parts.size() - 1] = QLatin1String(heap::brand::kLegacyName);
  parts[parts.size() - 2] = QLatin1String(heap::brand::kLegacyName);
  return parts.join(QLatin1Char('/'));
}

MoveResult moveLegacyData(const QString& newDir, const QString& legacyDir) {
  MoveResult r;
  r.from = legacyDir;
  r.to = newDir;
  if(legacyDir.isEmpty() || QFileInfo::exists(QDir(newDir).filePath(kState)) || !QFileInfo::exists(QDir(legacyDir).filePath(kState))) {
    return r;
  }
  // Moved once already: the new folder losing its state.json later (wiped by
  // hand) is not a reason to bring the old one back.
  if(QFileInfo::exists(QDir(legacyDir).filePath(QLatin1String(heap::brand::kMovedMarker)))) {
    return r;
  }
  if(legacyRunning(legacyDir)) {
    r.kind = MoveKind::Busy;
    return r;
  }

  // Copy beside the new folder, then move each top-level entry in: a copy
  // that stops half-way leaves the new folder without a state.json, so the
  // next launch simply tries again.
  const QString staging = QDir::cleanPath(newDir) + QStringLiteral(".moving");
  QDir(staging).removeRecursively();
  if(!copyTree(legacyDir, staging, &r.files, &r.error)) {
    QDir(staging).removeRecursively();
    r.kind = MoveKind::Failed;
    return r;
  }
  QDir().mkpath(newDir);
  const QDir in(staging);
  // state.json last: until it is there, the move has not happened.
  QStringList entries = in.entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot);
  entries.removeAll(kState);
  entries.append(kState);
  for(const QString& name : entries) {
    const QString target = QDir(newDir).filePath(name);
    if(QFileInfo::exists(target)) {
      if(QFileInfo(target).isDir() && QFileInfo(in.filePath(name)).isDir()) {
        // A folder this launch already made (logs): merge file by file.
        QDirIterator files(in.filePath(name), QDir::Files | QDir::Hidden | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while(files.hasNext()) {
          const QString f = files.next();
          const QString to = QDir(target).filePath(QDir(in.filePath(name)).relativeFilePath(f));
          QDir().mkpath(QFileInfo(to).absolutePath());
          if(!QFileInfo::exists(to)) {
            QFile::rename(f, to);
          }
        }
      }
      continue;  // what this launch wrote stays
    }
    if(!QFile::rename(in.filePath(name), target) && !QDir().rename(in.filePath(name), target)) {
      r.kind = MoveKind::Failed;
      r.error = QStringLiteral("could not move %1 into %2").arg(name, QDir::toNativeSeparators(newDir));
      QDir(staging).removeRecursively();
      return r;
    }
  }
  QDir(staging).removeRecursively();

  QSaveFile marker(QDir(legacyDir).filePath(QLatin1String(heap::brand::kMovedMarker)));
  if(marker.open(QIODevice::WriteOnly)) {
    marker.write(QStringLiteral("heap is now lowkey. On %1 everything in this folder was copied to\n%2\n"
                                "and lowkey works from there. This folder is kept as it was; you can delete it once\n"
                                "you no longer need to go back to heap 0.7.\n")
                     .arg(QDateTime::currentDateTime().toString(Qt::ISODate), QDir::toNativeSeparators(newDir))
                     .toUtf8());
    marker.commit();
  }
  r.kind = MoveKind::Moved;
  return r;
}

}  // namespace heap::platform::legacy
