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

// KNOW-12: [[C\# basics]] names the note "C# basics"; splitting on '#'
// missed it.
TEST_F(KnowledgeTest, Know12_EscapedHashLinkIsListedAsLinking) {
  AppController app;
  const QString note = app.newNote(QStringLiteral("C# basics"));
  app.tasks()->reset({makeTask(QStringLiteral("APP-1"), QStringLiteral("todo"), QStringLiteral("see [[C\\# basics]]"))});
  ASSERT_EQ(app.tasksLinkingToNote(note).size(), 1);
}

// KNOW-4: a rename rewrites [[Old]] in task descriptions, local notes and doc
// pages, in the same undo step as the notes.
TEST_F(KnowledgeTest, Know4_RenameRetargetsTaskAndPageLinks) {
  AppController app;
  const QString note = app.newNote(QStringLiteral("Design Doc"));
  Task local = makeTask(QStringLiteral("APP-3"), QStringLiteral("todo"));
  local.local.notes = QStringLiteral("mine: [[design doc#Risks]]");
  app.tasks()->reset({makeTask(QStringLiteral("APP-2"), QStringLiteral("todo"), QStringLiteral("spec: [[Design Doc]]")), local});
  const QString page = app.newDocPage(QStringLiteral("Runbook"));
  app.setDocPageBody(page, QStringLiteral("see [[Design Doc]]"));

  ASSERT_TRUE(app.renameNote(note, QStringLiteral("Design Spec")));

  EXPECT_EQ(app.taskById(QStringLiteral("APP-2")).value("desc").toString(), QStringLiteral("spec: [[Design Spec]]"));
  EXPECT_EQ(app.tasksLinkingToNote(note).size(), 2);
  EXPECT_EQ(app.docPageBody(page), QStringLiteral("see [[Design Spec]]"));
  app.undo();
  EXPECT_EQ(app.taskById(QStringLiteral("APP-2")).value("desc").toString(), QStringLiteral("spec: [[Design Doc]]"));
}

// IDIOT-KNOW-3: a rename onto another note's title in the same folder is
// refused; links that meant that note keep meaning it.
TEST_F(KnowledgeTest, IdiotKnow3_RenameOntoATakenTitleIsRefused) {
  AppController app;
  const QString alpha = app.newNote(QStringLiteral("Alpha"));
  const QString beta = app.newNote(QStringLiteral("Beta"));
  const QString gamma = app.newNote(QStringLiteral("Gamma"));
  app.setNoteBody(gamma, QStringLiteral("See [[Alpha]] and [[Beta]]."));
  EXPECT_TRUE(app.noteTitleTaken(QStringLiteral("beta"), QString(), alpha));
  EXPECT_FALSE(app.noteTitleTaken(QStringLiteral("Beta"), QString(), beta)) << "its own name is not taken";
  EXPECT_FALSE(app.renameNote(alpha, QStringLiteral("beta")));
  EXPECT_EQ(app.noteBody(gamma), QStringLiteral("See [[Alpha]] and [[Beta]]."));
  EXPECT_FALSE(app.renameNote(alpha, QStringLiteral("  ")));
  EXPECT_TRUE(app.renameNote(alpha, QStringLiteral("Delta")));
}

// IDIOT-KNOW-14: a second "+" over the untouched new note opens it again,
// and leaving it untouched leaves nothing behind; a note written in stays.
TEST_F(KnowledgeTest, IdiotKnow14_UntouchedNewNotesDoNotPileUp) {
  AppController app;
  app.notes()->reset({});
  const QString kept = app.newNote(QStringLiteral("Kept"));
  const QString first = app.newNote();
  EXPECT_EQ(app.newNote(), first);
  EXPECT_EQ(app.notes()->rowCount(), 2);
  app.setActiveNoteId(kept);
  EXPECT_EQ(app.notes()->indexOfId(first), -1);
  const QString written = app.newNote();
  app.setNotesState(app.notesState() + QStringLiteral("words"));
  app.setActiveNoteId(kept);
  EXPECT_GE(app.notes()->indexOfId(written), 0);
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
