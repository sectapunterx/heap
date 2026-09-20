// Docs as a tree of pages.
//
// Docs was a catalog: links, snippets and contacts, all of them one line long.
// There was nowhere to write the paragraph explaining why the link matters,
// which is the thing people actually need from a team's docs.
//
// The tree is a parent pointer and a fractional rank, for the same reasons the
// board uses one: a flat list is what a QAbstractListModel can carry, and
// moving one page should rewrite one page rather than renumber a level.

#include "AppController.h"
#include "Models.h"

#include <QApplication>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

class DocPageTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->docPages()->reset({});
  }

  void TearDown() override {
    app_.reset();
  }

  int count() const {
    return app_->docPages()->rowCount();
  }

  QStringList childIdsOf(const QString& parentId) const {
    QStringList out;
    for(const QVariant& v : app_->docPageChildren(parentId)) {
      out << v.toMap().value(QStringLiteral("id")).toString();
    }
    return out;
  }

  QString parentOf(const QString& id) const {
    const int row = app_->docPages()->indexOfId(id);
    return row >= 0 ? app_->docPages()->items().at(row).parentId : QString();
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(DocPageTest, APageIsCreatedAndOpened) {
  const QString id = app_->newDocPage(QStringLiteral("Runbook"));

  EXPECT_EQ(count(), 1);
  EXPECT_EQ(app_->activeDocPageId(), id);
}

TEST_F(DocPageTest, APageStartsWithItsHeading) {
  const QString id = app_->newDocPage(QStringLiteral("Runbook"));

  EXPECT_TRUE(app_->docPageBody(id).contains(QStringLiteral("# Runbook")));
}

TEST_F(DocPageTest, AnUntitledPageStillHasAName) {
  const QString id = app_->newDocPage();

  const int row = app_->docPages()->indexOfId(id);
  EXPECT_FALSE(app_->docPages()->items().at(row).title.isEmpty());
}

// ── The tree ──

TEST_F(DocPageTest, ARootPageIsAChildOfNothing) {
  const QString id = app_->newDocPage(QStringLiteral("Top"));

  EXPECT_EQ(childIdsOf(QString()), QStringList{id});
}

TEST_F(DocPageTest, AChildIsListedUnderItsParent) {
  const QString parent = app_->newDocPage(QStringLiteral("Top"));
  const QString child = app_->newDocPage(QStringLiteral("Under"), parent);

  EXPECT_EQ(childIdsOf(parent), QStringList{child});
  EXPECT_EQ(childIdsOf(QString()), QStringList{parent});
}

// So a row can draw a disclosure triangle without asking again.
TEST_F(DocPageTest, APageSaysWhetherItHasChildren) {
  const QString parent = app_->newDocPage(QStringLiteral("Top"));
  app_->newDocPage(QStringLiteral("Under"), parent);

  const QVariantList roots = app_->docPageChildren(QString());
  ASSERT_EQ(roots.size(), 1);
  EXPECT_TRUE(roots.at(0).toMap().value(QStringLiteral("hasChildren")).toBool());
}

// New pages go last, which is where a new thing belongs.
TEST_F(DocPageTest, NewPagesKeepTheirOrder) {
  const QString a = app_->newDocPage(QStringLiteral("A"));
  const QString b = app_->newDocPage(QStringLiteral("B"));
  const QString c = app_->newDocPage(QStringLiteral("C"));

  EXPECT_EQ(childIdsOf(QString()), (QStringList{a, b, c}));
}

// ── Moving ──

TEST_F(DocPageTest, MovingAPageChangesItsParent) {
  const QString parent = app_->newDocPage(QStringLiteral("Top"));
  const QString loose = app_->newDocPage(QStringLiteral("Loose"));

  app_->moveDocPage(loose, parent, QString());

  EXPECT_EQ(parentOf(loose), parent);
  EXPECT_EQ(childIdsOf(parent), QStringList{loose});
}

TEST_F(DocPageTest, MovingAPageBeforeASiblingPutsItThere) {
  const QString a = app_->newDocPage(QStringLiteral("A"));
  const QString b = app_->newDocPage(QStringLiteral("B"));
  const QString c = app_->newDocPage(QStringLiteral("C"));

  app_->moveDocPage(c, QString(), a);

  EXPECT_EQ(childIdsOf(QString()), (QStringList{c, a, b}));
}

TEST_F(DocPageTest, MovingWithNoTargetPutsItLast) {
  const QString a = app_->newDocPage(QStringLiteral("A"));
  const QString b = app_->newDocPage(QStringLiteral("B"));

  app_->moveDocPage(a, QString(), QString());

  EXPECT_EQ(childIdsOf(QString()), (QStringList{b, a}));
}

// A page dropped inside its own subtree would take the branch with it: nothing
// would reach it from the root, so the whole thing would vanish from the tree.
TEST_F(DocPageTest, APageCannotBeMovedIntoItself) {
  const QString parent = app_->newDocPage(QStringLiteral("Top"));

  app_->moveDocPage(parent, parent, QString());

  EXPECT_EQ(parentOf(parent), QString());
}

TEST_F(DocPageTest, APageCannotBeMovedIntoItsOwnDescendant) {
  const QString top = app_->newDocPage(QStringLiteral("Top"));
  const QString mid = app_->newDocPage(QStringLiteral("Mid"), top);
  const QString leaf = app_->newDocPage(QStringLiteral("Leaf"), mid);

  app_->moveDocPage(top, leaf, QString());

  EXPECT_EQ(parentOf(top), QString()) << "the branch must stay reachable from the root";
  EXPECT_EQ(childIdsOf(top), QStringList{mid});
}

TEST_F(DocPageTest, MovingSomethingThatIsNotThereDoesNothing) {
  const QString a = app_->newDocPage(QStringLiteral("A"));

  app_->moveDocPage(QStringLiteral("nobody"), a, QString());

  EXPECT_EQ(count(), 1);
}

// ── Deleting ──

TEST_F(DocPageTest, DeletingAPageRemovesIt) {
  const QString id = app_->newDocPage(QStringLiteral("Gone"));

  app_->deleteDocPage(id);

  EXPECT_EQ(count(), 0);
}

// A page whose parent is gone is unreachable in the tree and invisible
// everywhere else — deleted in every sense except the one that frees the space.
TEST_F(DocPageTest, DeletingAPageTakesItsSubtree) {
  const QString top = app_->newDocPage(QStringLiteral("Top"));
  const QString mid = app_->newDocPage(QStringLiteral("Mid"), top);
  app_->newDocPage(QStringLiteral("Leaf"), mid);
  ASSERT_EQ(count(), 3);

  app_->deleteDocPage(top);

  EXPECT_EQ(count(), 0);
}

TEST_F(DocPageTest, DeletingAPageLeavesItsSiblingsAlone) {
  const QString a = app_->newDocPage(QStringLiteral("A"));
  const QString b = app_->newDocPage(QStringLiteral("B"));

  app_->deleteDocPage(a);

  EXPECT_EQ(childIdsOf(QString()), QStringList{b});
}

TEST_F(DocPageTest, DeletingTheOpenPageOpensAnother) {
  const QString a = app_->newDocPage(QStringLiteral("A"));
  const QString b = app_->newDocPage(QStringLiteral("B"));
  app_->setActiveDocPageId(b);

  app_->deleteDocPage(b);

  EXPECT_EQ(app_->activeDocPageId(), a);
}

TEST_F(DocPageTest, DeletingTheLastPageLeavesNothingOpen) {
  const QString id = app_->newDocPage(QStringLiteral("Only"));

  app_->deleteDocPage(id);

  EXPECT_TRUE(app_->activeDocPageId().isEmpty());
}

// Deleting a subtree is one thing the user did.
TEST_F(DocPageTest, DeletingASubtreeIsOneUndoStep) {
  const QString top = app_->newDocPage(QStringLiteral("Top"));
  app_->newDocPage(QStringLiteral("Mid"), top);
  const int before = app_->undoDepth();

  app_->deleteDocPage(top);

  EXPECT_EQ(app_->undoDepth(), before + 1);
}

TEST_F(DocPageTest, UndoRestoresADeletedSubtree) {
  const QString top = app_->newDocPage(QStringLiteral("Top"));
  app_->newDocPage(QStringLiteral("Mid"), top);
  app_->deleteDocPage(top);
  ASSERT_EQ(count(), 0);

  app_->undo();

  EXPECT_EQ(count(), 2);
}

// ── Editing ──

TEST_F(DocPageTest, RenamingChangesTheTitle) {
  const QString id = app_->newDocPage(QStringLiteral("Old"));

  app_->renameDocPage(id, QStringLiteral("New"));

  const int row = app_->docPages()->indexOfId(id);
  EXPECT_EQ(app_->docPages()->items().at(row).title, QStringLiteral("New"));
}

TEST_F(DocPageTest, RenamingToNothingIsRefused) {
  const QString id = app_->newDocPage(QStringLiteral("Keep"));

  app_->renameDocPage(id, QStringLiteral("  "));

  const int row = app_->docPages()->indexOfId(id);
  EXPECT_EQ(app_->docPages()->items().at(row).title, QStringLiteral("Keep"));
}

TEST_F(DocPageTest, ABodyIsStoredAndFetched) {
  const QString id = app_->newDocPage(QStringLiteral("Runbook"));

  app_->setDocPageBody(id, QStringLiteral("the whole story"));

  EXPECT_EQ(app_->docPageBody(id), QStringLiteral("the whole story"));
}

// The model carries no bodies, for the same reason NoteModel does not: a tree
// of fifty pages would be fifty documents crossing the QML boundary.
TEST_F(DocPageTest, TheModelDoesNotCarryBodies) {
  app_->newDocPage(QStringLiteral("Runbook"));

  EXPECT_LT(app_->docPages()->roleOf(QStringLiteral("body")), 0);
  EXPECT_GE(app_->docPages()->roleOf(QStringLiteral("title")), 0);
  EXPECT_GE(app_->docPages()->roleOf(QStringLiteral("parentId")), 0);
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
