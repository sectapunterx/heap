// Knowledge (APP-269): what a note says about the tasks it names, which tasks
// link the note, and how [[targets]] are drawn.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QDir>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

Task makeTask(const QString& id, const QString& status, const QString& desc = QString()) {
  Task t;
  t.id = id;
  t.title = QStringLiteral("Title of ") + id;
  t.priority = QStringLiteral("P2");
  t.status = status;
  t.desc = desc;
  return t;
}

class KnowledgeTest : public ::testing::Test {
 protected:
  void SetUp() override {
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir(dir).removeRecursively();
    QDir().mkpath(dir);
  }
};

}  // namespace

TEST_F(KnowledgeTest, TasksInTheNoteCarryTheirColumn) {
  AppController app;
  app.tasks()->reset(
      {makeTask(QStringLiteral("APP-101"), QStringLiteral("prog")), makeTask(QStringLiteral("APP-108"), QStringLiteral("todo"))});
  const QVariantList refs = app.noteTaskRefs(QStringLiteral("A bug in [[APP-101]], see APP-108 and APP-999 and APP-101 again."));
  ASSERT_EQ(refs.size(), 2) << "an unknown key or a repeat was listed";
  EXPECT_EQ(refs[0].toMap().value("id").toString(), QStringLiteral("APP-101"));
  EXPECT_EQ(refs[0].toMap().value("category").toString(), QStringLiteral("prog"));
  EXPECT_FALSE(refs[0].toMap().value("statusName").toString().isEmpty());
  EXPECT_EQ(refs[1].toMap().value("id").toString(), QStringLiteral("APP-108"));
}

TEST_F(KnowledgeTest, WikiTargetsAreTaskChipsOrMissing) {
  AppController app;
  app.tasks()->reset({makeTask(QStringLiteral("APP-101"), QStringLiteral("done"))});
  const QString note = app.newNote(QStringLiteral("Rate limit"));
  ASSERT_FALSE(note.isEmpty());
  const QVariantMap t = app.wikiTargets(QStringLiteral("[[APP-101]] [[Rate limit]] [[Gone note]]"));
  ASSERT_TRUE(t.contains(QStringLiteral("APP-101")));
  EXPECT_EQ(t.value("APP-101").toMap().value("kind").toString(), QStringLiteral("task"));
  EXPECT_TRUE(t.value("APP-101").toMap().value("label").toString().endsWith(QStringLiteral("APP-101")));
  EXPECT_FALSE(t.contains(QStringLiteral("Rate limit"))) << "a note that exists is a plain link";
  ASSERT_TRUE(t.contains(QStringLiteral("Gone note")));
  EXPECT_EQ(t.value("Gone note").toMap().value("kind").toString(), QStringLiteral("missing"));
}

// A task that links the note by its title is a backlink of the note.
TEST_F(KnowledgeTest, TasksLinkingTheNoteAreBacklinks) {
  AppController app;
  const QString note = app.newNote(QStringLiteral("Rate limit"));
  Task linked = makeTask(QStringLiteral("APP-7"), QStringLiteral("todo"), QStringLiteral("Design in [[rate limit#Open questions]]"));
  Task other = makeTask(QStringLiteral("APP-8"), QStringLiteral("todo"), QStringLiteral("Not about it"));
  Task local = makeTask(QStringLiteral("APP-9"), QStringLiteral("todo"));
  local.local.notes = QStringLiteral("my note: [[Rate limit]]");
  app.tasks()->reset({linked, other, local});
  const QVariantList hits = app.tasksLinkingToNote(note);
  ASSERT_EQ(hits.size(), 2);
  EXPECT_EQ(hits[0].toMap().value("id").toString(), QStringLiteral("APP-7"));
  EXPECT_EQ(hits[1].toMap().value("id").toString(), QStringLiteral("APP-9"));
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
