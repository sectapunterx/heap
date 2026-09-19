// Data-directory resolution (heap::paths).
//
// Everything heap writes — state.json, backups/, logs/ and the keychain-less
// secrets.json fallback — resolves through heap::paths::dataDir(). The override
// is what lets a test run, a screenshot session or a bug repro point the app at
// a throwaway directory instead of the owner's real profile, so the contract is
// worth pinning down: the default matches the platform location, a relative
// path is made absolute, and an empty argument never silently redirects
// anything.
//
// setDataDir() is deliberately one-way (it runs once, from main(), before any
// other thread exists), so the whole lifecycle lives in a single test rather
// than in separate cases whose order would matter.

#include "platform/Paths.h"

#include <QDir>
#include <QStandardPaths>

#include <gtest/gtest.h>

TEST(PathsTest, OverrideLifecycle) {
  const QString platformDefault = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);

  // Before anything is set, the platform location is used verbatim.
  EXPECT_FALSE(heap::paths::dataDirOverridden());
  EXPECT_EQ(heap::paths::dataDir(), platformDefault);

  // An empty argument is a no-op: a missing --data-dir and an unset
  // HEAP_DATA_DIR must not redirect the profile.
  heap::paths::setDataDir(QString());
  EXPECT_FALSE(heap::paths::dataDirOverridden());
  EXPECT_EQ(heap::paths::dataDir(), platformDefault);

  // A relative path is resolved against the working directory, so the value
  // stays valid no matter who later chdir's.
  heap::paths::setDataDir(QStringLiteral("heap-test-profile"));
  EXPECT_TRUE(heap::paths::dataDirOverridden());
  EXPECT_EQ(heap::paths::dataDir(), QDir::current().absoluteFilePath("heap-test-profile"));
  EXPECT_NE(heap::paths::dataDir(), platformDefault);

  // A later absolute path wins, and a trailing separator is normalised away so
  // callers can append "/logs" without producing a doubled slash.
  const QString absolute = QDir::tempPath() + QStringLiteral("/heap-paths-test");
  heap::paths::setDataDir(absolute + QLatin1Char('/'));
  EXPECT_EQ(heap::paths::dataDir(), QDir(absolute).absolutePath());
  EXPECT_FALSE(heap::paths::dataDir().endsWith(QLatin1Char('/')));

  // The override survives an empty call — a stray no-op must not reset it back
  // to the real profile.
  heap::paths::setDataDir(QString());
  EXPECT_TRUE(heap::paths::dataDirOverridden());
  EXPECT_EQ(heap::paths::dataDir(), QDir(absolute).absolutePath());
}
