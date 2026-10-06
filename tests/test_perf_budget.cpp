// Performance budget gate (APP-161).
//
// Measures the operations a heavy user feels, on a generated 10k-task profile,
// takes the median of several runs of each, prints one table of measured vs
// budget, and fails when a median exceeds its budget (PerfBudgets.h).
//
// The gate is only armed where the numbers mean something: an optimised build
// without sanitizers or coverage (HEAP_PERF_GATE, set by tests/CMakeLists.txt).
// Elsewhere — the ASan job, the coverage run, a Debug build — the table is
// still printed and nothing is asserted. HEAP_PERF_REPORT_ONLY=1 disarms it by
// hand, e.g. on a laptop on battery.
//
// Also covers the opt-in perf log (diag/PerfLog.h) the app writes with
// HEAP_PERF_LOG=1 / --perf-log.

#include "AppController.h"
#include "BenchData.h"
#include "PerfBudgets.h"
#include "StateSerializer.h"
#include "TaskFilterProxy.h"

#include "chrono/ChronoParser.h"
#include "diag/PerfLog.h"
#include "markdown/MdDocument.h"

#include <QApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

#include <algorithm>
#include <cstdio>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#ifndef HEAP_PERF_GATE
#define HEAP_PERF_GATE 0
#endif

namespace {

using heap::perf::Budget;
using heap::perf::kBudgets;

QString appDataDir() {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

bool gateArmed() {
  return HEAP_PERF_GATE != 0 && qEnvironmentVariable("HEAP_PERF_REPORT_ONLY") != QLatin1String("1");
}

// Median of `runs` timings of `body`, in ms. `prepare` runs before each timing
// and is not counted.
double medianMs(int runs, const std::function<void(int)>& body, const std::function<void(int)>& prepare = {}) {
  std::vector<double> samples;
  samples.reserve(static_cast<size_t>(runs));
  for(int i = 0; i < runs; ++i) {
    if(prepare) {
      prepare(i);
    }
    QElapsedTimer timer;
    timer.start();
    body(i);
    samples.push_back(static_cast<double>(timer.nsecsElapsed()) / 1e6);
  }
  std::ranges::sort(samples);
  return samples.at(samples.size() / 2);
}

const Budget& budgetFor(const std::string& name) {
  for(const Budget& b : kBudgets) {
    if(name == b.name) {
      return b;
    }
  }
  ADD_FAILURE() << "no budget named " << name;
  static const Budget none{.name = "?", .what = "?", .localMs = 0, .budgetMs = 0};
  return none;
}

// A median over its budget is measured again, up to twice, and the best one
// counts: a real regression is over budget every time, a runner that was busy
// for a moment is not.
constexpr int kOverBudgetRetries = 2;

double measureAgainstBudget(const std::string& name,
                            int runs,
                            const std::function<void(int)>& body,
                            const std::function<void(int)>& prepare = {}) {
  const double budget = budgetFor(name).budgetMs;
  double best = medianMs(runs, body, prepare);
  for(int retry = 0; retry < kOverBudgetRetries && best > budget; ++retry) {
    best = std::min(best, medianMs(runs, body, prepare));
  }
  return best;
}

QStringList captureStrings(int n) {
  static const QStringList templates = {
      QStringLiteral("Review PR %1 tomorrow at 10am"),
      QStringLiteral("call Bob about invoice %1 next friday 3pm"),
      QStringLiteral("standup notes %1 every weekday 9:30"),
      QStringLiteral("ship release %1 in 2 days"),
      QStringLiteral("fix flaky test %1 on monday"),
      QStringLiteral("1:1 with Ann %1 at 16:00 in 3 weeks"),
      QStringLiteral("созвон по задаче %1 завтра в 15:00"),
      QStringLiteral("дедлайн отчёта %1 в пятницу"),
      QStringLiteral("plain title with no date %1"),
      QStringLiteral("rotate keys %1 on 2026-11-03 at 08:15"),
  };
  QStringList out;
  out.reserve(n);
  for(int i = 0; i < n; ++i) {
    out << templates.at(i % templates.size()).arg(i);
  }
  return out;
}

const QStringList& columnStatuses() {
  static const QStringList ids = {QStringLiteral("todo"),
                                  QStringLiteral("prog"),
                                  QStringLiteral("half"),
                                  QStringLiteral("review"),
                                  QStringLiteral("blocked"),
                                  QStringLiteral("done"),
                                  QStringLiteral("backlog")};
  return ids;
}

}  // namespace

TEST(PerfBudget, HeavyProfileOperationsWithinBudget) {
  QDir(appDataDir()).removeRecursively();
  QDir().mkpath(appDataDir());

  const QVector<Task> tasks = heap::bench::makeTasks(heap::perf::kPerfTaskCount);
  const QVector<Note> notes = heap::bench::makeNotes(heap::perf::kPerfNoteCount, heap::perf::kPerfNoteChars);

  // Write the profile once through the app itself, so state.json is exactly
  // what a real 10k-task user has on disk.
  {
    AppController seed;
    seed.tasks()->reset(tasks);
    seed.notes()->reset(notes);
    seed.setCrumbUser(QStringLiteral("perf-seed"));
    seed.flushSave();
  }
  const QString statePath = appDataDir() + QStringLiteral("/state.json");
  QFile stateFile(statePath);
  ASSERT_TRUE(stateFile.open(QIODevice::ReadOnly)) << qPrintable(statePath);
  const QByteArray stateBytes = stateFile.readAll();
  stateFile.close();

  std::map<std::string, double> measured;

  // ── state.parse: bytes → document → every profile, as a cold open does.
  int parsedTasks = 0;
  measured["state.parse"] = measureAgainstBudget("state.parse", 3, [&](int) {
    const QJsonObject root = QJsonDocument::fromJson(stateBytes).object();
    int n = 0;
    for(const auto& v : root.value(QStringLiteral("profiles")).toArray()) {
      n += static_cast<int>(heap::state::profileFromJson(v.toObject()).tasks.size());
    }
    parsedTasks = n;
  });
  EXPECT_EQ(parsedTasks, heap::perf::kPerfTaskCount);

  // ── state.boot: the whole controller coming up on that file.
  std::unique_ptr<AppController> app;
  measured["state.boot"] = measureAgainstBudget(
      "state.boot",
      3,
      [&](int) {
        app = std::make_unique<AppController>();
      },
      [&](int) {
        app.reset();  // the previous instance's teardown is not counted
      });
  ASSERT_EQ(app->tasks()->rowCount(), heap::perf::kPerfTaskCount);
  // >=: the controller may add a note of its own (an adopted scratch note).
  ASSERT_GE(app->notes()->rowCount(), heap::perf::kPerfNoteCount);

  // ── state.save: the debounced save, armed the way any edit arms it.
  app->flushSave();
  measured["state.save"] = measureAgainstBudget(
      "state.save",
      3,
      [&](int) {
        app->flushSave();
      },
      [&](int i) {
        app->setCrumbUser(QStringLiteral("perf-") + QString::number(i));
      });

  // ── search.fulltext: a query nothing matches walks every section of every
  // note — the worst case for the palette's notes search.
  EXPECT_TRUE(app->searchFullText(QStringLiteral("zzqx nomatch"), 0).isEmpty());
  measured["search.fulltext"] = measureAgainstBudget("search.fulltext", 5, [&](int) {
    app->searchFullText(QStringLiteral("zzqx nomatch"), 0);
  });

  // ── filter.*: the board — one proxy per column over the whole task model.
  std::vector<std::unique_ptr<TaskFilterProxy>> columns;
  for(const QString& s : columnStatuses()) {
    auto p = std::make_unique<TaskFilterProxy>();
    p->setSourceModel(app->tasks());
    p->setStatus(s);
    columns.push_back(std::move(p));
  }
  const auto typeEverywhere = [&columns](const QString& text) {
    for(auto& c : columns) {
      c->setSearchText(text);
    }
  };
  typeEverywhere(QStringLiteral("x"));  // warm the haystack cache, as the first render does
  measured["filter.keystroke"] = measureAgainstBudget("filter.keystroke", 7, [&](int i) {
    typeEverywhere(QStringLiteral("number 1") + QString::number(i % 10));
  });
  typeEverywhere(QString());
  measured["filter.reset"] = measureAgainstBudget("filter.reset", 5, [&](int) {
    app->tasks()->reset(tasks);
  });
  int visible = 0;
  for(const auto& c : columns) {
    visible += c->rowCount();
  }
  EXPECT_EQ(visible, heap::perf::kPerfTaskCount);
  columns.clear();

  // ── chrono.capture1k: what the capture popup runs on every title.
  const heap::chrono::ChronoParser parser{QLocale(QLocale::English)};
  const QStringList inputs = captureStrings(heap::perf::kPerfCaptureCount);
  const QDateTime now(QDate(2026, 10, 5), QTime(12, 0));
  int recognised = 0;
  measured["chrono.capture1k"] = measureAgainstBudget("chrono.capture1k", 5, [&](int) {
    int ok = 0;
    for(const QString& s : inputs) {
      ok += parser.parse(s, now).ok ? 1 : 0;
    }
    recognised = ok;
  });
  EXPECT_GT(recognised, heap::perf::kPerfCaptureCount / 2);

  // ── markdown.render: a large note through the editor's document — parse,
  // block rows with their HTML, outline.
  heap::md::MdDocument doc;
  const QString big = heap::bench::makeNoteBody(0, heap::perf::kPerfLargeNoteChars);
  doc.setText(big);
  doc.flush();
  measured["markdown.render"] = measureAgainstBudget("markdown.render", 5, [&](int i) {
    doc.setText(big + QStringLiteral("\nedit %1\n").arg(i));
    doc.flush();
  });
  EXPECT_FALSE(doc.outlineList().isEmpty());

  // ── the table, then the gate.
  const bool armed = gateArmed();
  std::printf("\n[ perf-budget ] %d tasks, %d notes, gate %s\n",
              heap::perf::kPerfTaskCount,
              heap::perf::kPerfNoteCount,
              armed ? "ARMED" : "report-only (unoptimised/sanitized build or HEAP_PERF_REPORT_ONLY=1)");
  std::printf("[ perf-budget ] %-18s %10s %10s %10s %6s  %s\n", "name", "median ms", "budget ms", "local ms", "use", "what");
  for(const Budget& b : kBudgets) {
    const auto it = measured.find(b.name);
    const double ms = it == measured.end() ? -1.0 : it->second;
    const double use = b.budgetMs > 0 ? ms / b.budgetMs * 100.0 : 0.0;
    std::printf("[ perf-budget ] %-18s %10.1f %10.1f %10.1f %5.0f%%  %s%s\n",
                b.name,
                ms,
                b.budgetMs,
                b.localMs,
                use,
                b.what,
                ms > b.budgetMs ? "  <-- OVER BUDGET" : "");
  }
  (void)std::fflush(stdout);

  for(const Budget& b : kBudgets) {
    ASSERT_TRUE(measured.count(b.name) == 1) << "budget " << b.name << " was never measured";
  }
  for(const auto& [name, ms] : measured) {
    const Budget& b = budgetFor(name);
    if(armed) {
      EXPECT_LE(ms, b.budgetMs) << name << " took " << ms << " ms (median), budget " << b.budgetMs
                                << " ms. Find what got slower before touching tests/PerfBudgets.h.";
    }
  }
}

// ── The opt-in perf log the app writes (diag/PerfLog.h) ──

class PerfLogTest : public ::testing::Test {
 protected:
  void SetUp() override {
    heap::perf::resetForTests();
  }

  void TearDown() override {
    heap::perf::resetForTests();
  }
};

TEST_F(PerfLogTest, OffByDefaultAndThenEveryCallIsANoOp) {
  if(qEnvironmentVariable("HEAP_PERF_LOG") == QLatin1String("1")) {
    GTEST_SKIP() << "HEAP_PERF_LOG=1 in this environment";
  }
  EXPECT_FALSE(heap::perf::enabled());
  heap::perf::begin(QStringLiteral("capture"));
  EXPECT_EQ(heap::perf::end(QStringLiteral("capture")), -1);
}

TEST_F(PerfLogTest, ASpanEndsOnceAndOnlyAfterItBegan) {
  heap::perf::setEnabled(true);
  EXPECT_EQ(heap::perf::end(QStringLiteral("capture")), -1) << "no span was begun";
  heap::perf::begin(QStringLiteral("capture"));
  EXPECT_GE(heap::perf::end(QStringLiteral("capture")), 0);
  EXPECT_EQ(heap::perf::end(QStringLiteral("capture")), -1) << "a span ends once — a second frame must not log again";
}

TEST_F(PerfLogTest, NamedSpansAreIndependent) {
  heap::perf::setEnabled(true);
  heap::perf::begin(QStringLiteral("capture"));
  heap::perf::begin(QStringLiteral("capture-notes"));
  EXPECT_GE(heap::perf::end(QStringLiteral("capture-notes")), 0);
  EXPECT_GE(heap::perf::end(QStringLiteral("capture")), 0);
}

TEST_F(PerfLogTest, BeginIfIdleKeepsAFreshHotkeyStartButReplacesAStaleOne) {
  heap::perf::setEnabled(true);
  heap::perf::begin(QStringLiteral("capture"));  // the global hotkey
  QElapsedTimer wait;
  wait.start();
  while(wait.elapsed() < 30) {}
  heap::perf::beginIfIdle(QStringLiteral("capture"), 10'000);  // the popup starting to show
  EXPECT_GE(heap::perf::end(QStringLiteral("capture")), 30) << "the popup restarted a span the hotkey had begun";

  heap::perf::begin(QStringLiteral("capture"));  // an end that never came
  wait.restart();
  while(wait.elapsed() < 30) {}
  heap::perf::beginIfIdle(QStringLiteral("capture"), 10);
  EXPECT_LT(heap::perf::end(QStringLiteral("capture")), 30) << "a stale start was kept";
}

TEST_F(PerfLogTest, ProcessClockRunsFromMarkProcessStart) {
  heap::perf::markProcessStart();
  EXPECT_GE(heap::perf::sinceProcessStart(), 0);
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  const QApplication qapp(argc, argv);

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
