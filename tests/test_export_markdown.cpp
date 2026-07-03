// Markdown export of the active profile (HEAP-53).
//
// The Ctrl+Shift+E shortcut bound to copyActiveProfileMarkdownToClipboard()
// used to call a method that did not exist (a QML TypeError, silent no-op).
// These tests pin the restored method: it renders the active profile — tasks
// grouped by column, people, notes — and puts it on the clipboard.
//
// Headless via offscreen QPA + AppDataLocation test mode, like the other
// AppController suites.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QVector>

#include <gtest/gtest.h>

namespace {

Task makeTask(const QString& id, const QString& title, const QString& priority, const QString& status) {
  Task t;
  t.id = id;
  t.title = title;
  t.priority = priority;
  t.status = status;
  return t;
}

Person makePerson(const QString& name, const QString& role) {
  Person p;
  p.id = name.toLower();
  p.name = name;
  p.role = role;
  return p;
}

}  // namespace

class MarkdownExportTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->tasks()->reset({});
    app_->people()->reset({});
  }

  void TearDown() override {
    app_.reset();
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(MarkdownExportTest, RendersTasksPeopleAndNotesToClipboard) {
  app_->tasks()->reset({
      makeTask(QStringLiteral("T-1"), QStringLiteral("First thing"), QStringLiteral("P0"), QStringLiteral("todo")),
      makeTask(QStringLiteral("T-2"), QStringLiteral("Second thing"), QStringLiteral("P2"), QStringLiteral("done")),
  });
  app_->people()->reset({makePerson(QStringLiteral("Alice"), QStringLiteral("Reviewer"))});
  app_->setNotesState(QStringLiteral("remember the milk"));

  app_->copyActiveProfileMarkdownToClipboard();
  const QString md = QGuiApplication::clipboard()->text();

  EXPECT_TRUE(md.contains(QStringLiteral("## Tasks"))) << md.toStdString();
  EXPECT_TRUE(md.contains(QStringLiteral("`T-1`")));
  EXPECT_TRUE(md.contains(QStringLiteral("**[P0]**")));
  EXPECT_TRUE(md.contains(QStringLiteral("First thing")));
  EXPECT_TRUE(md.contains(QStringLiteral("## People")));
  EXPECT_TRUE(md.contains(QStringLiteral("Alice")));
  EXPECT_TRUE(md.contains(QStringLiteral("## Notes")));
  EXPECT_TRUE(md.contains(QStringLiteral("remember the milk")));
}

TEST_F(MarkdownExportTest, ArchivedTasksAreExcluded) {
  Task archived = makeTask(QStringLiteral("T-OLD"), QStringLiteral("hidden"), QStringLiteral("P3"), QStringLiteral("done"));
  archived.archived = true;
  app_->tasks()->reset({
      makeTask(QStringLiteral("T-NEW"), QStringLiteral("visible"), QStringLiteral("P1"), QStringLiteral("todo")),
      archived,
  });

  app_->copyActiveProfileMarkdownToClipboard();
  const QString md = QGuiApplication::clipboard()->text();

  EXPECT_TRUE(md.contains(QStringLiteral("`T-NEW`")));
  EXPECT_FALSE(md.contains(QStringLiteral("`T-OLD`")));
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
