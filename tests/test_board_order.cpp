// Manual card order on the board.
//
// A card's position in its column is a fractional rank (src/board/Rank.h), and
// moveTaskTo places one immediately above a named neighbour — which is what a
// drop between two cards means. These cases pin the placement arithmetic
// through the real controller: the pure midpoint maths lives in test_rank.cpp.
//
// Headless via offscreen QPA + AppDataLocation test mode.

#include "AppController.h"
#include "Models.h"
#include "StateSerializer.h"

#include <QApplication>
#include <QDir>
#include <QStandardPaths>
#include <QStringList>
#include <QTemporaryDir>

#include <gtest/gtest.h>

#include <algorithm>

namespace {

Task makeTask(const QString& id, const QString& status, double rank) {
  Task t;
  t.id = id;
  t.title = id;
  t.priority = QStringLiteral("P2");
  t.status = status;
  t.branch = QStringLiteral("feat/x");  // lets a move into "review" pass
  t.rank = rank;
  return t;
}

}  // namespace

class BoardOrderTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
  }

  void TearDown() override {
    app_.reset();
  }

  // Seeds one column with the given ids, ranked the way the v4→v5 migration
  // would have ranked them.
  void seedColumn(const QStringList& ids, const QString& statusId) {
    QVector<Task> tasks;
    for(int i = 0; i < ids.size(); ++i) {
      tasks.append(makeTask(ids.at(i), statusId, (i + 1) * heap::state::kRankStep));
    }
    app_->tasks()->reset(tasks);
  }

  // Ids of one column, in the order the board shows them.
  QStringList order(const QString& statusId) const {
    QVector<Task> ordered;
    for(const Task& t : app_->tasks()->items()) {
      if(t.status == statusId) {
        ordered.append(t);
      }
    }
    std::sort(ordered.begin(), ordered.end(), [](const Task& a, const Task& b) {
      return a.rank != b.rank ? a.rank < b.rank : a.id < b.id;
    });
    QStringList ids;
    for(const Task& t : ordered) {
      ids << t.id;
    }
    return ids;
  }

  double rankOf(const QString& id) const {
    return app_->tasks()->items().at(app_->tasks()->indexOfId(id)).rank;
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(BoardOrderTest, PlacesACardAboveItsTarget) {
  seedColumn({QStringLiteral("A"), QStringLiteral("B"), QStringLiteral("C")}, QStringLiteral("todo"));

  app_->moveTaskTo(QStringLiteral("C"), QStringLiteral("todo"), QStringLiteral("B"));

  EXPECT_EQ(order(QStringLiteral("todo")), (QStringList{QStringLiteral("A"), QStringLiteral("C"), QStringLiteral("B")}));
}

TEST_F(BoardOrderTest, MoveToTheTopOfAColumn) {
  seedColumn({QStringLiteral("A"), QStringLiteral("B"), QStringLiteral("C")}, QStringLiteral("todo"));

  app_->moveTaskTo(QStringLiteral("C"), QStringLiteral("todo"), QStringLiteral("A"));

  EXPECT_EQ(order(QStringLiteral("todo")).first(), QStringLiteral("C"));
  EXPECT_GT(rankOf(QStringLiteral("C")), 0.0) << "the top of a column is still a positive rank";
}

// An empty target is what dropping below every card hands over.
TEST_F(BoardOrderTest, NoTargetMeansTheEndOfTheColumn) {
  seedColumn({QStringLiteral("A"), QStringLiteral("B"), QStringLiteral("C")}, QStringLiteral("todo"));

  app_->moveTaskTo(QStringLiteral("A"), QStringLiteral("todo"), QString());

  EXPECT_EQ(order(QStringLiteral("todo")).last(), QStringLiteral("A"));
}

// Dropping a card one place down has to mean one place down. The neighbours
// are computed with the dragged card removed, so "before C" is unambiguous —
// counting it would make this move look like no move at all.
TEST_F(BoardOrderTest, OnePlaceDown) {
  seedColumn({QStringLiteral("A"), QStringLiteral("B"), QStringLiteral("C")}, QStringLiteral("todo"));

  app_->moveTaskTo(QStringLiteral("A"), QStringLiteral("todo"), QStringLiteral("C"));

  EXPECT_EQ(order(QStringLiteral("todo")), (QStringList{QStringLiteral("B"), QStringLiteral("A"), QStringLiteral("C")}));
}

TEST_F(BoardOrderTest, MovingToItsOwnPositionChangesNothing) {
  seedColumn({QStringLiteral("A"), QStringLiteral("B"), QStringLiteral("C")}, QStringLiteral("todo"));

  app_->moveTaskTo(QStringLiteral("B"), QStringLiteral("todo"), QStringLiteral("C"));

  EXPECT_EQ(order(QStringLiteral("todo")), (QStringList{QStringLiteral("A"), QStringLiteral("B"), QStringLiteral("C")}));
}

TEST_F(BoardOrderTest, MovingToAnotherColumnCarriesThePosition) {
  app_->tasks()->reset({makeTask(QStringLiteral("P0"), QStringLiteral("prog"), heap::state::kRankStep),
                        makeTask(QStringLiteral("P1"), QStringLiteral("prog"), 2 * heap::state::kRankStep),
                        makeTask(QStringLiteral("M"), QStringLiteral("todo"), heap::state::kRankStep)});

  app_->moveTaskTo(QStringLiteral("M"), QStringLiteral("prog"), QStringLiteral("P1"));

  EXPECT_EQ(order(QStringLiteral("prog")), (QStringList{QStringLiteral("P0"), QStringLiteral("M"), QStringLiteral("P1")}));
  EXPECT_EQ(app_->tasks()->items().at(app_->tasks()->indexOfId(QStringLiteral("M"))).status, QStringLiteral("prog"));
}

TEST_F(BoardOrderTest, AnUnknownColumnIsANoop) {
  seedColumn({QStringLiteral("A"), QStringLiteral("B")}, QStringLiteral("todo"));
  const QStringList before = order(QStringLiteral("todo"));

  app_->moveTaskTo(QStringLiteral("A"), QStringLiteral("ghost"), QString());

  EXPECT_EQ(order(QStringLiteral("todo")), before);
}

TEST_F(BoardOrderTest, AnUnknownTaskIsANoop) {
  seedColumn({QStringLiteral("A"), QStringLiteral("B")}, QStringLiteral("todo"));
  const QStringList before = order(QStringLiteral("todo"));

  app_->moveTaskTo(QStringLiteral("ghost"), QStringLiteral("todo"), QStringLiteral("A"));

  EXPECT_EQ(order(QStringLiteral("todo")), before);
}

// Repeatedly dropping into the same gap halves it each time. Well before the
// midpoint stops being distinct the column rebalances, and the order holds.
TEST_F(BoardOrderTest, RepeatedDropsIntoTheSameGapKeepTheOrder) {
  seedColumn({QStringLiteral("A"), QStringLiteral("B"), QStringLiteral("X")}, QStringLiteral("todo"));

  for(int i = 0; i < 120; ++i) {
    app_->moveTaskTo(QStringLiteral("X"), QStringLiteral("todo"), QString());            // to the end
    app_->moveTaskTo(QStringLiteral("X"), QStringLiteral("todo"), QStringLiteral("B"));  // back into the A..B gap
  }

  EXPECT_EQ(order(QStringLiteral("todo")), (QStringList{QStringLiteral("A"), QStringLiteral("X"), QStringLiteral("B")}));
  EXPECT_GT(rankOf(QStringLiteral("X")), rankOf(QStringLiteral("A")));
  EXPECT_LT(rankOf(QStringLiteral("X")), rankOf(QStringLiteral("B")));
}

// A bulk drop keeps the block in its own order rather than reversing it.
TEST_F(BoardOrderTest, ABulkDropKeepsTheBlocksOrder) {
  seedColumn({QStringLiteral("A"), QStringLiteral("B"), QStringLiteral("C"), QStringLiteral("D")}, QStringLiteral("todo"));
  app_->setSelectedTaskIds({QStringLiteral("C"), QStringLiteral("D")});

  app_->moveSelectedTasksTo(QStringLiteral("todo"), QStringLiteral("A"));

  EXPECT_EQ(order(QStringLiteral("todo")),
            (QStringList{QStringLiteral("C"), QStringLiteral("D"), QStringLiteral("A"), QStringLiteral("B")}));
}

// A new card is the thing the user just thought of; appending it below a long
// column is a card they then have to go looking for.
TEST_F(BoardOrderTest, ANewTaskLandsAtTheTopOfItsColumn) {
  seedColumn({QStringLiteral("A"), QStringLiteral("B")}, QStringLiteral("todo"));

  QVariantMap draft = app_->newTaskDraft(QStringLiteral("todo"));
  draft["title"] = QStringLiteral("just thought of this");
  const QString newId = draft.value(QStringLiteral("id")).toString();
  app_->saveTask(draft);

  EXPECT_EQ(order(QStringLiteral("todo")).first(), newId);
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
