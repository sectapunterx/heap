// Input-latency budget for a large board (audit 2026-09-30, TASKS-23).
//
// At 3k tasks every keystroke in the search box cost ~250 ms and a query
// ~360 ms: each board column is a TaskFilterProxy over the whole task model, and
// each one rebuilt every row's lowercase search haystack (title + description +
// labels + …) from scratch, per keystroke, per column. The model now caches the
// haystack per row and the proxies read it without a QVariant round trip.
//
// These budgets are generous against a developer machine (a keystroke across
// all columns measures a few ms there) because CI runners are slower and
// contended. They exist to catch the return of an O(rows × columns × text)
// rebuild, not to benchmark. The measured numbers are always printed.

#include "AppController.h"
#include "TaskFilterProxy.h"

#include <QApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

#include <algorithm>
#include <iostream>
#include <memory>
#include <vector>

namespace {

constexpr int kTaskCount = 3000;
constexpr qint64 kKeystrokeBudgetMs = 150;
constexpr qint64 kRowEditBudgetMs = 60;
constexpr qint64 kPaletteBudgetMs = 250;

const QStringList& statusIds() {
  static const QStringList ids = {QStringLiteral("todo"),
                                  QStringLiteral("prog"),
                                  QStringLiteral("half"),
                                  QStringLiteral("review"),
                                  QStringLiteral("blocked"),
                                  QStringLiteral("done"),
                                  QStringLiteral("backlog")};
  return ids;
}

QVector<Task> makeTasks(int n) {
  QVector<Task> out;
  out.reserve(n);
  const QDateTime base = QDateTime(QDate::currentDate().addDays(-30), QTime(0, 0));
  for(int i = 0; i < n; ++i) {
    Task t;
    t.id = QStringLiteral("SC-") + QString::number(i + 1);
    t.title = QStringLiteral("Scale %1 refactor module").arg(i);
    t.desc = QStringLiteral("lorem ipsum ").repeated(10 + (i % 20));
    t.priority = QStringLiteral("P%1").arg(i % 4);
    t.status = statusIds().at(i % statusIds().size());
    if(i % 3 != 0) {
      t.dueAt = base.addDays(i % 90);
      t.scheduledAt = t.dueAt;
    }
    t.rank = 1024.0 * (i + 1);
    if(i % 2 == 0) {
      t.labels = {Label{QStringLiteral("l") + QString::number(i % 6), QStringLiteral("#5aa9e6")}};
    }
    out.append(t);
  }
  return out;
}

struct Board {
  std::vector<std::unique_ptr<TaskFilterProxy>> columns;

  explicit Board(TaskModel* model) {
    for(const QString& s : statusIds()) {
      auto p = std::make_unique<TaskFilterProxy>();
      p->setSourceModel(model);
      p->setStatus(s);
      columns.push_back(std::move(p));
    }
  }

  // What one keystroke does on the board: every column gets the new text.
  qint64 type(const QString& text) {
    QElapsedTimer timer;
    timer.start();
    for(auto& c : columns) {
      c->setSearchText(text);
    }
    return timer.elapsed();
  }

  int visible() const {
    int n = 0;
    for(const auto& c : columns) {
      n += c->rowCount();
    }
    return n;
  }
};

// Types `text` one character at a time; returns the slowest keystroke.
qint64 worstKeystroke(Board& board, const QString& text) {
  qint64 worst = 0;
  for(int i = 1; i <= text.size(); ++i) {
    worst = std::max(worst, board.type(text.left(i)));
  }
  return worst;
}

class FilterBench : public ::testing::Test {
 protected:
  void SetUp() override {
    QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)).removeRecursively();
    app = std::make_unique<AppController>();
    app->tasks()->reset(makeTasks(kTaskCount));
  }

  std::unique_ptr<AppController> app;
};

}  // namespace

TEST_F(FilterBench, SearchKeystrokeAcrossAllColumnsWithinBudget) {
  Board board(app->tasks());
  ASSERT_EQ(board.visible(), kTaskCount);
  board.type(QStringLiteral("x"));  // warm the haystack cache the first render would
  board.type(QString());

  const qint64 search = worstKeystroke(board, QStringLiteral("scale 12"));
  const int hits = board.visible();
  board.type(QString());
  const qint64 query = worstKeystroke(board, QStringLiteral("priority:p0 deadline:<7d"));
  board.type(QString());

  std::cout << "[ filter-latency ] tasks=" << kTaskCount << " columns=" << board.columns.size() << " search-worst=" << search
            << "ms query-worst=" << query << "ms budget=" << kKeystrokeBudgetMs << "ms" << std::endl;
  // "scale 12" is SC-13, SC-121..SC-130, SC-1201..SC-1300: 111 tasks.
  EXPECT_EQ(hits, 111);
  EXPECT_LE(search, kKeystrokeBudgetMs);
  EXPECT_LE(query, kKeystrokeBudgetMs);
}

// One card edited while the board is filtered: the proxies re-test one row,
// and the cached haystack for that row must be the new text, not the old.
TEST_F(FilterBench, SingleRowEditIsCheapAndRefreshesTheHaystack) {
  Board board(app->tasks());
  board.type(QStringLiteral("zebra"));
  ASSERT_EQ(board.visible(), 0);

  Task t = app->tasks()->items().at(42);
  t.title = QStringLiteral("Zebra crossing");
  QElapsedTimer timer;
  timer.start();
  app->tasks()->upsert(t);
  const qint64 edit = timer.elapsed();
  EXPECT_EQ(board.visible(), 1) << "an edited title was not searchable — stale haystack cache";

  t.title = QStringLiteral("Plain again");
  app->tasks()->upsert(t);
  EXPECT_EQ(board.visible(), 0) << "the old title still matched — stale haystack cache";

  // Rows shifting under the cache: insert at the top, remove from the middle.
  Task fresh;
  fresh.id = QStringLiteral("NEW-1");
  fresh.title = QStringLiteral("zebra on top");
  fresh.status = QStringLiteral("todo");
  app->tasks()->insertAt(0, fresh);
  EXPECT_EQ(board.visible(), 1);
  app->tasks()->removeById(QStringLiteral("SC-10"));
  EXPECT_EQ(board.visible(), 1);
  board.type(QStringLiteral("scale 11 refactor"));
  EXPECT_EQ(board.visible(), 1) << "rows after a removed one read their neighbour's haystack";  // SC-12 only
  app->tasks()->removeById(QStringLiteral("NEW-1"));
  board.type(QStringLiteral("zebra"));
  EXPECT_EQ(board.visible(), 0);

  std::cout << "[ filter-latency ] single-row edit with " << board.columns.size() << " filtered columns=" << edit
            << "ms budget=" << kRowEditBudgetMs << "ms" << std::endl;
  EXPECT_LE(edit, kRowEditBudgetMs);
}

// Ctrl+K builds its whole entry list on open.
TEST_F(FilterBench, CommandPaletteEntriesWithinBudget) {
  app->commandPaletteEntries();  // warm
  QElapsedTimer timer;
  timer.start();
  const QVariantList entries = app->commandPaletteEntries();
  const qint64 elapsed = timer.elapsed();
  std::cout << "[ filter-latency ] palette entries=" << entries.size() << " build=" << elapsed << "ms budget=" << kPaletteBudgetMs << "ms"
            << std::endl;
  EXPECT_GE(entries.size(), kTaskCount);
  EXPECT_LE(elapsed, kPaletteBudgetMs);
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
