// heap → lowkey (APP-280): the first launch copies a 0.7.x data folder into
// the new one — once, all of it, and never while heap 0.7 still runs on it.

#include "platform/Brand.h"
#include "platform/LegacyData.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLockFile>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

using heap::platform::legacy::legacyDirFor;
using heap::platform::legacy::MoveKind;
using heap::platform::legacy::moveLegacyData;

void writeFile(const QString& path, const QByteArray& bytes) {
  QDir().mkpath(QFileInfo(path).absolutePath());
  QFile f(path);
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write(bytes);
}

QByteArray readFile(const QString& path) {
  QFile f(path);
  return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}

class LegacyData : public ::testing::Test {
 protected:
  void SetUp() override {
    ASSERT_TRUE(root_.isValid());
    newDir_ = root_.filePath(QStringLiteral("lowkey/lowkey"));
    oldDir_ = root_.filePath(QStringLiteral("heap/heap"));
  }

  // A 0.7.x folder: state, a backup, a time-machine snapshot, an attachment,
  // the file-fallback secrets and a lock file that must not travel.
  void makeOldFolder() {
    writeFile(oldDir_ + "/state.json", R"({"schemaVersion":11})");
    writeFile(oldDir_ + "/backups/state-20261001-120000.json", "backup");
    writeFile(oldDir_ + "/history/2026-10-01T12-00.json.gz", "snapshot");
    writeFile(oldDir_ + "/attachments/0123456789abcdef0123456789abcdef.png", "png");
    writeFile(oldDir_ + "/secrets.json", "{}");
    writeFile(oldDir_ + "/logs/heap.log", "old log");
  }

  QTemporaryDir root_;
  QString newDir_;
  QString oldDir_;
};

}  // namespace

TEST_F(LegacyData, TheOldFolderSitsBesideTheNewOne) {
  EXPECT_EQ(QDir::cleanPath(legacyDirFor(newDir_)), QDir::cleanPath(oldDir_));
  EXPECT_TRUE(legacyDirFor(root_.filePath(QStringLiteral("somewhere/else"))).isEmpty())
      << "a folder that is not lowkey/lowkey has no heap one beside it";
}

TEST_F(LegacyData, EverythingIsCopiedAndTheOldFolderStays) {
  makeOldFolder();
  const auto r = moveLegacyData(newDir_, oldDir_);
  ASSERT_EQ(r.kind, MoveKind::Moved) << r.error.toStdString();
  EXPECT_EQ(readFile(newDir_ + "/state.json"), QByteArray(R"({"schemaVersion":11})"));
  EXPECT_EQ(readFile(newDir_ + "/backups/state-20261001-120000.json"), QByteArray("backup"));
  EXPECT_EQ(readFile(newDir_ + "/history/2026-10-01T12-00.json.gz"), QByteArray("snapshot"));
  EXPECT_EQ(readFile(newDir_ + "/attachments/0123456789abcdef0123456789abcdef.png"), QByteArray("png"));
  EXPECT_EQ(readFile(newDir_ + "/secrets.json"), QByteArray("{}"));
  // The old folder is untouched apart from the marker.
  EXPECT_TRUE(QFileInfo::exists(oldDir_ + "/state.json"));
  EXPECT_TRUE(QFileInfo::exists(oldDir_ + "/" + QLatin1String(heap::brand::kMovedMarker)));
  EXPECT_FALSE(QFileInfo::exists(newDir_ + ".moving")) << "the staging folder is gone";
}

TEST_F(LegacyData, ASecondLaunchDoesNotCopyAgain) {
  makeOldFolder();
  ASSERT_EQ(moveLegacyData(newDir_, oldDir_).kind, MoveKind::Moved);
  writeFile(newDir_ + "/state.json", R"({"schemaVersion":12})");  // lowkey saved since
  writeFile(oldDir_ + "/state.json", R"({"schemaVersion":11,"changed":true})");
  EXPECT_EQ(moveLegacyData(newDir_, oldDir_).kind, MoveKind::NothingToDo);
  EXPECT_EQ(readFile(newDir_ + "/state.json"), QByteArray(R"({"schemaVersion":12})"));
}

TEST_F(LegacyData, AWipedNewFolderDoesNotBringTheOldDataBack) {
  makeOldFolder();
  ASSERT_EQ(moveLegacyData(newDir_, oldDir_).kind, MoveKind::Moved);
  QDir(newDir_).removeRecursively();
  EXPECT_EQ(moveLegacyData(newDir_, oldDir_).kind, MoveKind::NothingToDo);
  EXPECT_FALSE(QFileInfo::exists(newDir_ + "/state.json"));
}

TEST_F(LegacyData, ANewInstallWithoutHeapDoesNothing) {
  EXPECT_EQ(moveLegacyData(newDir_, oldDir_).kind, MoveKind::NothingToDo);
  EXPECT_FALSE(QFileInfo::exists(newDir_ + "/state.json"));
}

TEST_F(LegacyData, NothingMovesWhileHeapStillRunsOnTheOldFolder) {
  makeOldFolder();
  QLockFile held(oldDir_ + "/" + QLatin1String(heap::brand::kLegacyLockFile));
  ASSERT_TRUE(held.tryLock(0));
  EXPECT_EQ(moveLegacyData(newDir_, oldDir_).kind, MoveKind::Busy);
  EXPECT_FALSE(QFileInfo::exists(newDir_ + "/state.json"));
  held.unlock();
  EXPECT_EQ(moveLegacyData(newDir_, oldDir_).kind, MoveKind::Moved);
}

TEST_F(LegacyData, FilesThisLaunchAlreadyWroteAreKept) {
  makeOldFolder();
  writeFile(newDir_ + "/logs/lowkey.log", "new log");  // the logger runs before the move
  ASSERT_EQ(moveLegacyData(newDir_, oldDir_).kind, MoveKind::Moved);
  EXPECT_EQ(readFile(newDir_ + "/logs/lowkey.log"), QByteArray("new log"));
  EXPECT_EQ(readFile(newDir_ + "/logs/heap.log"), QByteArray("old log"));
  EXPECT_FALSE(QFileInfo::exists(newDir_ + "/" + QLatin1String(heap::brand::kLegacyLockFile)));
}

int main(int argc, char** argv) {
  QCoreApplication app(argc, argv);
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
