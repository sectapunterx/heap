// Corruption / crash recovery for AppController::loadStateOnStart() (HEAP-50).
//
// Guards the trust-critical rule: a state.json that exists but is unreadable or
// unparseable must NEVER be silently replaced by the demo seed. Instead the app
// recovers from the newest valid backup, or — failing that — quarantines the
// damaged file (state.corrupt-*.json) and boots a fresh profile.
//
// Runs headless via the same QApplication + offscreen QPA + QStandardPaths
// test-mode pattern as the selection / notes suites, so it never touches the
// user's real AppDataLocation.

#include "AppController.h"

#include <QApplication>
#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QVariantMap>

#include <gtest/gtest.h>

namespace {

QString appDataDir() {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

bool writeFile(const QString& path, const QByteArray& bytes) {
  QFile f(path);
  if(!f.open(QIODevice::WriteOnly)) {
    return false;
  }
  f.write(bytes);
  f.close();
  return true;
}

QByteArray readFile(const QString& path) {
  QFile f(path);
  if(!f.open(QIODevice::ReadOnly)) {
    return {};
  }
  const QByteArray b = f.readAll();
  f.close();
  return b;
}

QStringList corruptFiles(const QString& dir) {
  return QDir(dir).entryList({QStringLiteral("state.corrupt-*.json")}, QDir::Files);
}

QString firstProfileName(AppController& app) {
  const QVariantList ps = app.profiles();
  return ps.isEmpty() ? QString() : ps.first().toMap().value(QStringLiteral("name")).toString();
}

}  // namespace

class PersistenceTest : public ::testing::Test {
 protected:
  void SetUp() override {
    // Every test starts from an empty AppDataLocation — no state.json, no
    // backups, no leftover quarantine files from a previous test or run.
    const QString dir = appDataDir();
    QDir(dir).removeRecursively();
    QDir().mkpath(dir);
  }
};

// A valid state.json loads and its contents win over the demo seed; nothing is
// quarantined.
TEST_F(PersistenceTest, ValidStateLoadsWithoutQuarantine) {
  {
    AppController app;
    app.setCrumbUser(QStringLiteral("MARK_VALID"));
    app.flushSave();
  }  // destructor also flushes — state.json is valid and marked

  AppController app2;
  EXPECT_EQ(app2.crumbUser(), QStringLiteral("MARK_VALID"));
  EXPECT_TRUE(corruptFiles(appDataDir()).isEmpty());
}

// A corrupt state.json with a good backup available recovers the backup's data
// (proven by a marker) instead of seeding demo, and quarantines the bad file.
TEST_F(PersistenceTest, RecoversFromNewestBackupWhenStateCorrupt) {
  const QString dir = appDataDir();

  // 1) Produce a schema-valid state.json carrying a distinctive marker.
  {
    AppController app;
    app.setCrumbUser(QStringLiteral("RECOVERED_MARKER"));
    app.flushSave();
  }
  const QByteArray good = readFile(dir + QStringLiteral("/state.json"));
  ASSERT_FALSE(good.isEmpty());

  // 2) Stash it as a backup, then clobber the live state.json.
  ASSERT_TRUE(QDir().mkpath(dir + QStringLiteral("/backups")));
  ASSERT_TRUE(writeFile(dir + QStringLiteral("/backups/state-20240101-120000.json"), good));
  ASSERT_TRUE(writeFile(dir + QStringLiteral("/state.json"), QByteArray("{ this is not valid json")));

  // 3) Boot: recover the marker from the backup, quarantine the corrupt file.
  AppController app2;
  EXPECT_EQ(app2.crumbUser(), QStringLiteral("RECOVERED_MARKER"));
  EXPECT_FALSE(corruptFiles(dir).isEmpty());
}

// A corrupt state.json with NO backup preserves the damaged file and boots a
// fresh Example profile — never a silent wipe.
TEST_F(PersistenceTest, QuarantinesCorruptStateWhenNoBackup) {
  const QString dir = appDataDir();
  ASSERT_TRUE(writeFile(dir + QStringLiteral("/state.json"), QByteArray("garbage{{{ not json")));

  AppController app;
  // Did not adopt any recovered marker; booted the demo profile instead.
  EXPECT_NE(app.crumbUser(), QStringLiteral("RECOVERED_MARKER"));
  EXPECT_EQ(firstProfileName(app), QStringLiteral("Example"));
  // The damaged original is preserved, not overwritten.
  EXPECT_FALSE(corruptFiles(dir).isEmpty());
}

// An absent state.json is a genuine first run: seed the demo, quarantine
// nothing.
TEST_F(PersistenceTest, AbsentStateIsCleanFirstRun) {
  const QString dir = appDataDir();
  AppController app;
  EXPECT_TRUE(corruptFiles(dir).isEmpty());
  EXPECT_EQ(firstProfileName(app), QStringLiteral("Example"));
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  QApplication qapp(argc, argv);

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
