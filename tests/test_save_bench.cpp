// Save-latency budget for a large profile (HEAP-104 epic DoD).
//
// heap writes the whole profile as one JSON document on every debounced save. If
// that write cannot hold a human-imperceptible budget at a realistic ceiling of
// 10k tasks, the monolithic state file has to be segmented — a scope decision,
// not something this test should paper over. So the budget is asserted, and the
// measured number is always printed.
//
// The budget is deliberately loose relative to a developer machine: CI runners
// have slow, contended disks, and this test must not flake. The number that
// matters is the one printed to stdout.

#include "AppController.h"

#include <QApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

#include <algorithm>
#include <iostream>
#include <limits>

namespace {

constexpr int kTaskCount = 10000;
constexpr qint64 kBudgetMs = 2000;

QString appDataDir() {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QVector<Task> makeTasks(int n) {
  QVector<Task> out;
  out.reserve(n);
  const QDateTime base(QDate(2026, 7, 9), QTime(9, 0));
  for(int i = 0; i < n; ++i) {
    Task t;
    t.id = QStringLiteral("BENCH-") + QString::number(i);
    t.title = QStringLiteral("Task number %1 with a realistic title length").arg(i);
    t.desc = QStringLiteral("Several lines of description text, of the sort a real ticket carries.\nSecond line.");
    t.priority = QStringLiteral("P%1").arg(i % 4);
    t.status = (i % 3 == 0) ? QStringLiteral("todo") : QStringLiteral("prog");
    t.scheduledAt = base.addDays(i % 90);
    t.dueAt = base.addDays((i % 90) + 1);
    t.hasTime = (i % 2) == 0;
    t.branch = QStringLiteral("feature/bench-") + QString::number(i);
    t.statusChangedAt = base;
    t.trackedSeconds = i;
    t.recurrence = (i % 10 == 0) ? QStringLiteral("every:weekday") : QString();
    if(i % 5 == 0) {
      t.externalId = QString::number(i);
      t.externalUrl = QStringLiteral("https://example.invalid/") + t.externalId;
      t.externalProvider = QStringLiteral("github");
    }
    t.labels = {Label{QStringLiteral("bench"), QStringLiteral("#5cc2dd")}, Label{QStringLiteral("p") + QString::number(i % 4), QString()}};
    t.estimateMinutes = 30 + (i % 240);
    out.append(t);
  }
  return out;
}

}  // namespace

TEST(SaveLatency, TenThousandTasksSaveWithinBudget) {
  QDir(appDataDir()).removeRecursively();
  QDir().mkpath(appDataDir());

  AppController app;
  app.tasks()->reset(makeTasks(kTaskCount));

  // flushSave() only writes when a save is pending, so each run arms the
  // debounced save the way any edit would, then times the flush: snapshot the
  // active profile, serialize the whole document, write it atomically.
  const auto armAndTime = [&app](int i) {
    app.setCrumbUser(QStringLiteral("bench-") + QString::number(i));
    QElapsedTimer timer;
    timer.start();
    app.flushSave();
    return timer.elapsed();
  };

  armAndTime(-1);  // warm the page cache and the profile snapshot

  qint64 best = std::numeric_limits<qint64>::max();
  qint64 total = 0;
  constexpr int kRuns = 5;
  for(int i = 0; i < kRuns; ++i) {
    const qint64 elapsed = armAndTime(i);
    ASSERT_GT(elapsed, -1);
    best = std::min(best, elapsed);
    total += elapsed;
  }

  const qint64 size = QFileInfo(appDataDir() + "/state.json").size();
  std::cout << "[ save-latency ] tasks=" << kTaskCount << " state.json=" << (size / 1024) << " KiB"
            << " best=" << best << "ms mean=" << (total / kRuns) << "ms budget=" << kBudgetMs << "ms" << std::endl;

  EXPECT_LE(best, kBudgetMs) << "A 10k-task profile no longer saves within the budget. This is the signal to "
                                "segment the state file — report it, do not raise the budget.";
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
