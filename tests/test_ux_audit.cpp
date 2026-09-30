// UX audit fixes (2026-09-30) that live in C++: the first-run language, toast
// kinds, and Russian labels that were half English.

#include "AppController.h"

#include "text/UiLanguage.h"

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

using heap::text::uiLanguageFor;

// UX-13: a ru-RU system starts in Russian; the first language heap speaks in
// the system's preference list wins; anything else is English.
TEST(UiLanguage, PicksRussianForRussianSystems) {
  EXPECT_EQ(uiLanguageFor({QStringLiteral("ru-RU")}), QStringLiteral("ru"));
  EXPECT_EQ(uiLanguageFor({QStringLiteral("ru")}), QStringLiteral("ru"));
  EXPECT_EQ(uiLanguageFor({QStringLiteral("ru_UA")}), QStringLiteral("ru"));
  EXPECT_EQ(uiLanguageFor({QStringLiteral("de-DE"), QStringLiteral("ru-RU")}), QStringLiteral("ru"));
}

TEST(UiLanguage, EnglishOtherwise) {
  EXPECT_EQ(uiLanguageFor({QStringLiteral("en-US")}), QStringLiteral("en"));
  EXPECT_EQ(uiLanguageFor({QStringLiteral("en-GB"), QStringLiteral("ru-RU")}), QStringLiteral("en"));
  EXPECT_EQ(uiLanguageFor({QStringLiteral("de-DE")}), QStringLiteral("en"));
  EXPECT_EQ(uiLanguageFor({}), QStringLiteral("en"));
  // "rus" is not "ru-…".
  EXPECT_EQ(uiLanguageFor({QStringLiteral("rust")}), QStringLiteral("en"));
}

class UxAuditTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
  }

  void TearDown() override {
    app_->setLanguage(QStringLiteral("en"));
  }

  std::unique_ptr<AppController> app_;
};

// UX-16: a refused action says so as a warning, not as a plain notice.
TEST_F(UxAuditTest, RefusalToastsCarryAKind) {
  const QVariantList sts = app_->statuses();
  ASSERT_FALSE(sts.isEmpty());
  const QString taken = sts.first().toMap().value("name").toString();
  QSignalSpy spy(app_.get(), &AppController::toast);
  app_->addStatus(taken);
  ASSERT_GE(spy.count(), 1);
  EXPECT_EQ(spy.last().at(1).toString(), QStringLiteral("warning"));
}

// UX-11: the hotkey catalog in Russian has no English view or panel names.
TEST_F(UxAuditTest, RussianShortcutLabelsAreRussian) {
  app_->setLanguage(QStringLiteral("ru"));
  const QRegularExpression english(
      QStringLiteral("\\b(Board|Timeline|Week|Month|Docs|Notes|Settings|Tweaks|Hotkeys|"
                     "Command Palette|Archive|Quick-capture)\\b"));
  for(const QVariant& v : app_->shortcuts()) {
    const QVariantMap m = v.toMap();
    const QString label = m.value("label").toString();
    const QString desc = m.value("description").toString();
    EXPECT_FALSE(english.match(label).hasMatch()) << label.toStdString();
    EXPECT_FALSE(english.match(desc).hasMatch()) << desc.toStdString();
  }
}

// UX-11: the breadcrumb's week is localized and is a real ISO week.
TEST_F(UxAuditTest, SprintCrumbIsTheIsoWeek) {
  const int week = app_->today().weekNumber();
  app_->setLanguage(QStringLiteral("en"));
  EXPECT_EQ(app_->sprintLabel(), QStringLiteral("wk %1").arg(week));
  app_->setLanguage(QStringLiteral("ru"));
  EXPECT_EQ(app_->sprintLabel(), QStringLiteral("нед. %1").arg(week));
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
