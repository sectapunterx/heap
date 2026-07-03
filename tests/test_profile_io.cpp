// Profile export / import round-trip for calendar events (HEAP-54).
//
// Events live in a global pool, so profileToJson() could not see them and a
// profile export silently dropped the entire calendar. These tests pin the
// fix: export includes the events attributed to the active profile, and import
// restores them into the global pool re-attributed to the imported profile
// with fresh ids.
//
// Headless via offscreen QPA + AppDataLocation test mode.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QDate>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QVector>

#include <gtest/gtest.h>

namespace {

CalEvent makeEvent(const QString& id, const QString& title, const QString& profileId) {
  CalEvent e;
  e.id = id;
  e.title = title;
  e.type = QStringLiteral("sync");
  e.start = 9.0;
  e.end = 10.0;
  e.date = QDate(2026, 5, 19);
  e.profileId = profileId;
  return e;
}

}  // namespace

class ProfileIoTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
  }

  void TearDown() override {
    app_.reset();
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(ProfileIoTest, ExportIncludesProfileEventsAndImportRestoresThem) {
  const QString active = app_->activeProfileId();
  app_->events()->reset({makeEvent(QStringLiteral("ev-src"), QStringLiteral("Standup XYZ"), active)});

  const QString json = app_->exportActiveProfileJson();
  ASSERT_FALSE(json.isEmpty());
  EXPECT_TRUE(json.contains(QStringLiteral("\"events\"")));
  EXPECT_TRUE(json.contains(QStringLiteral("Standup XYZ")));

  const int before = app_->events()->rowCount();
  const QString err = app_->importProfileFromJson(json, /*activate=*/false);
  EXPECT_TRUE(err.isEmpty()) << err.toStdString();
  EXPECT_GT(app_->events()->rowCount(), before);

  // The imported profile is the newest one; its events are in the global pool,
  // re-attributed to it and given a fresh id (never the source "ev-src").
  const QVariantList profs = app_->profiles();
  ASSERT_FALSE(profs.isEmpty());
  const QString newId = profs.last().toMap().value(QStringLiteral("id")).toString();

  int matched = 0;
  for(const CalEvent& ev : app_->events()->items()) {
    if(ev.title == QStringLiteral("Standup XYZ") && ev.profileId == newId) {
      ++matched;
      EXPECT_NE(ev.id, QStringLiteral("ev-src"));
      EXPECT_TRUE(ev.id.startsWith(QStringLiteral("ev-")));
    }
  }
  EXPECT_EQ(matched, 1);
}

TEST_F(ProfileIoTest, ExportExcludesOtherProfilesEvents) {
  const QString active = app_->activeProfileId();
  app_->events()->reset({
      makeEvent(QStringLiteral("ev-mine"), QStringLiteral("MineEvent"), active),
      makeEvent(QStringLiteral("ev-other"), QStringLiteral("OtherEvent"), QStringLiteral("some-other-profile")),
  });

  const QString json = app_->exportActiveProfileJson();
  EXPECT_TRUE(json.contains(QStringLiteral("MineEvent")));
  EXPECT_FALSE(json.contains(QStringLiteral("OtherEvent")));
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  QApplication qapp(argc, argv);

  const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  if(!appData.isEmpty()) {
    QFile::remove(appData + QStringLiteral("/state.json"));
    QDir(appData + QStringLiteral("/backups")).removeRecursively();
  }

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
