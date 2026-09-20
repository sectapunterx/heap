// Duplicating a task, and dependencies between tasks.
//
// A duplicate has to bring across what the user wrote and drop what identifies
// the original — above all its tracker link, because a copy that still mirrors
// someone's issue would push status changes onto it.
//
// Dependencies store only the "blocks" direction. "Blocked by" is a reverse
// lookup, so a relationship is one fact rather than two that can drift apart.
//
// Headless via offscreen QPA + AppDataLocation test mode.

#include "AppController.h"
#include "Models.h"
#include "StateSerializer.h"

#include <QApplication>
#include <QStandardPaths>
#include <QSet>
#include <QStringList>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

Task makeTask(const QString& id, const QString& status) {
  Task t;
  t.id = id;
  t.title = id;
  t.priority = QStringLiteral("P2");
  t.status = status;
  t.rank = heap::state::kRankStep;
  return t;
}

}  // namespace

class TaskLinkTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->tasks()->reset({makeTask(QStringLiteral("A"), QStringLiteral("todo")), makeTask(QStringLiteral("B"), QStringLiteral("todo"))});
  }

  void TearDown() override {
    app_.reset();
  }

  const Task* byId(const QString& id) const {
    const int row = app_->tasks()->indexOfId(id);
    return row < 0 ? nullptr : &app_->tasks()->items().at(row);
  }

  std::unique_ptr<AppController> app_;
};

// ─── duplicate ────────────────────────────────────────────────────────

TEST_F(TaskLinkTest, DuplicateCopiesWhatTheUserWrote) {
  Task t = makeTask(QStringLiteral("SRC"), QStringLiteral("prog"));
  t.title = QStringLiteral("Write the thing");
  t.desc = QStringLiteral("- [ ] step one\n- [ ] step two");
  t.priority = QStringLiteral("P0");
  t.estimateMinutes = 90;
  t.labels = {Label{QStringLiteral("infra"), QStringLiteral("#5cc2dd")}};
  app_->tasks()->reset({t});

  app_->duplicateTask(QStringLiteral("SRC"));

  ASSERT_EQ(app_->tasks()->rowCount(), 2);
  const Task* copy = nullptr;
  for(const Task& x : app_->tasks()->items()) {
    if(x.id != QStringLiteral("SRC")) {
      copy = &x;
    }
  }
  ASSERT_NE(copy, nullptr);
  EXPECT_EQ(copy->desc, t.desc);
  EXPECT_EQ(copy->priority, QStringLiteral("P0"));
  EXPECT_EQ(copy->status, QStringLiteral("prog"));
  EXPECT_EQ(copy->estimateMinutes, 90);
  EXPECT_EQ(copy->labels, t.labels);
  EXPECT_TRUE(copy->title.contains(QStringLiteral("Write the thing")));
}

TEST_F(TaskLinkTest, DuplicateGetsItsOwnId) {
  app_->duplicateTask(QStringLiteral("A"));
  ASSERT_EQ(app_->tasks()->rowCount(), 3);
  QSet<QString> ids;
  for(const Task& x : app_->tasks()->items()) {
    ids.insert(x.id);
  }
  EXPECT_EQ(ids.size(), app_->tasks()->rowCount()) << "ids must be unique: an upsert on a taken id destroys that task";
}

// The important one. A copy that still carries the tracker link would push
// status changes onto someone else's issue.
TEST_F(TaskLinkTest, DuplicateDropsTheTrackerLink) {
  Task t = makeTask(QStringLiteral("SRC"), QStringLiteral("todo"));
  t.externalId = QStringLiteral("68");
  t.externalUrl = QStringLiteral("https://example.invalid/68");
  t.externalProvider = QStringLiteral("github");
  t.assignee = QStringLiteral("ada");
  t.externalMeta.author = QStringLiteral("grace");
  app_->tasks()->reset({t});

  app_->duplicateTask(QStringLiteral("SRC"));

  for(const Task& x : app_->tasks()->items()) {
    if(x.id == QStringLiteral("SRC")) {
      continue;
    }
    EXPECT_TRUE(x.externalId.isEmpty());
    EXPECT_TRUE(x.externalProvider.isEmpty());
    EXPECT_TRUE(x.assignee.isEmpty());
    EXPECT_EQ(x.externalMeta, ExternalMeta{});
  }
}

// A duplicate is a new task: no time has been spent on it and it has not been
// sitting in its column for however long the original has.
TEST_F(TaskLinkTest, DuplicateStartsFresh) {
  Task t = makeTask(QStringLiteral("SRC"), QStringLiteral("todo"));
  t.trackedSeconds = 4242;
  t.timerStartedAt = QDateTime::currentDateTime();
  t.statusChangedAt = QDateTime::currentDateTime().addDays(-30);
  app_->tasks()->reset({t});

  app_->duplicateTask(QStringLiteral("SRC"));

  for(const Task& x : app_->tasks()->items()) {
    if(x.id == QStringLiteral("SRC")) {
      continue;
    }
    EXPECT_EQ(x.trackedSeconds, 0);
    EXPECT_FALSE(x.timerStartedAt.isValid());
    EXPECT_GT(x.statusChangedAt, t.statusChangedAt);
  }
}

// Links point out of a task. A copy that kept them would claim to block the
// same work, which is not what duplicating a card means.
TEST_F(TaskLinkTest, DuplicateDropsOutgoingLinks) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));
  app_->duplicateTask(QStringLiteral("A"));

  for(const Task& x : app_->tasks()->items()) {
    if(x.id == QStringLiteral("A")) {
      continue;
    }
    EXPECT_TRUE(x.links.isEmpty());
  }
}

TEST_F(TaskLinkTest, DuplicateLandsBelowTheOriginal) {
  app_->tasks()->reset({makeTask(QStringLiteral("A"), QStringLiteral("todo")), makeTask(QStringLiteral("B"), QStringLiteral("todo"))});
  Task b = *byId(QStringLiteral("B"));
  b.rank = 2 * heap::state::kRankStep;
  app_->tasks()->upsert(b);

  app_->duplicateTask(QStringLiteral("A"));

  const Task* copy = nullptr;
  for(const Task& x : app_->tasks()->items()) {
    if(x.id != QStringLiteral("A") && x.id != QStringLiteral("B")) {
      copy = &x;
    }
  }
  ASSERT_NE(copy, nullptr);
  EXPECT_GT(copy->rank, byId(QStringLiteral("A"))->rank);
  EXPECT_LT(copy->rank, byId(QStringLiteral("B"))->rank);
}

TEST_F(TaskLinkTest, DuplicateOfAnUnknownTaskIsANoop) {
  app_->duplicateTask(QStringLiteral("ghost"));
  EXPECT_EQ(app_->tasks()->rowCount(), 2);
}

// ─── links ────────────────────────────────────────────────────────────

TEST_F(TaskLinkTest, LinkIsStoredOnTheBlocker) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));

  ASSERT_EQ(byId(QStringLiteral("A"))->links.size(), 1);
  EXPECT_EQ(byId(QStringLiteral("A"))->links.at(0).targetId, QStringLiteral("B"));
  EXPECT_TRUE(byId(QStringLiteral("B"))->links.isEmpty()) << "only one direction is stored";
}

TEST_F(TaskLinkTest, BlockedByIsTheReverseLookup) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));

  EXPECT_EQ(app_->blockedBy(QStringLiteral("B")), QStringList{QStringLiteral("A")});
  EXPECT_TRUE(app_->blockedBy(QStringLiteral("A")).isEmpty());
}

TEST_F(TaskLinkTest, LinkingTwiceDoesNotDuplicateIt) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));
  EXPECT_EQ(byId(QStringLiteral("A"))->links.size(), 1);
}

TEST_F(TaskLinkTest, ATaskCannotBlockItself) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("A"));
  EXPECT_TRUE(byId(QStringLiteral("A"))->links.isEmpty());
}

TEST_F(TaskLinkTest, LinkingAnUnknownTaskIsANoop) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("ghost"));
  EXPECT_TRUE(byId(QStringLiteral("A"))->links.isEmpty());
}

TEST_F(TaskLinkTest, UnlinkRemovesIt) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));
  app_->unlinkTasks(QStringLiteral("A"), QStringLiteral("B"));
  EXPECT_TRUE(byId(QStringLiteral("A"))->links.isEmpty());
  EXPECT_TRUE(app_->blockedBy(QStringLiteral("B")).isEmpty());
}

TEST_F(TaskLinkTest, LinkingIsUndoable) {
  app_->clearPendingUndo();
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));
  ASSERT_EQ(byId(QStringLiteral("A"))->links.size(), 1);

  app_->undo();
  EXPECT_TRUE(byId(QStringLiteral("A"))->links.isEmpty());
}

// ─── the badge ────────────────────────────────────────────────────────
// A finished blocker stops blocking. Otherwise the badge would have to be
// cleared by hand and would quietly stop meaning anything.

TEST_F(TaskLinkTest, AnOpenBlockerBlocks) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));
  EXPECT_TRUE(app_->isBlockedByOpenTask(QStringLiteral("B")));
}

TEST_F(TaskLinkTest, ADoneBlockerDoesNot) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));
  app_->moveTask(QStringLiteral("A"), QStringLiteral("done"));
  EXPECT_FALSE(app_->isBlockedByOpenTask(QStringLiteral("B")));
}

TEST_F(TaskLinkTest, AnArchivedBlockerDoesNot) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));
  app_->setArchived(QStringLiteral("A"), true);
  EXPECT_FALSE(app_->isBlockedByOpenTask(QStringLiteral("B")));
}

TEST_F(TaskLinkTest, OneOpenBlockerAmongFinishedOnesStillBlocks) {
  app_->tasks()->reset({makeTask(QStringLiteral("A"), QStringLiteral("todo")), makeTask(QStringLiteral("B"), QStringLiteral("todo")),
                        makeTask(QStringLiteral("C"), QStringLiteral("todo"))});
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("C"));
  app_->linkTasks(QStringLiteral("B"), QStringLiteral("C"));
  app_->moveTask(QStringLiteral("A"), QStringLiteral("done"));

  EXPECT_TRUE(app_->isBlockedByOpenTask(QStringLiteral("C")));
}

TEST_F(TaskLinkTest, AnUnlinkedTaskIsNotBlocked) {
  EXPECT_FALSE(app_->isBlockedByOpenTask(QStringLiteral("B")));
}

// A link survives the round trip, or the dependency quietly disappears on the
// next launch.
TEST_F(TaskLinkTest, LinksSurviveASaveAndReload) {
  app_->linkTasks(QStringLiteral("A"), QStringLiteral("B"));
  app_->flushSave();

  AppController reopened;
  EXPECT_EQ(reopened.blockedBy(QStringLiteral("B")), QStringList{QStringLiteral("A")});
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
