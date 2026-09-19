// Markdown parser: performance budget.
//
// The notes editor re-parses on a debounce while the user types, so parse cost
// is felt directly as input lag. The blob a heavy user accumulates is the size
// that matters — a single profile's notes are one string, and they only grow.
//
// Like test_save_bench.cpp, the assertion is deliberately loose because CI
// runners vary and a flaky perf test gets ignored rather than fixed. The
// printed number is the signal; the budget only catches a change that made
// things categorically slower. If this starts failing, the answer is to parse
// incrementally rather than to raise the budget.

#include "markdown/MdParser.h"
#include "markdown/MdSourceMap.h"

#include <QElapsedTimer>
#include <QString>

#include <gtest/gtest.h>

using namespace heap::md;

namespace {

// Roughly the mix a real note has: headings, prose, lists, tables and code,
// rather than one construct repeated.
QString buildDocument(int approximateBytes) {
  const QString unit = QStringLiteral(
      "## Section heading\n"
      "\n"
      "A paragraph with **strong** text, _emphasis_, `inline code`, a\n"
      "[link](https://example.com), a [[wiki link]] and some Cyrillic: текст.\n"
      "\n"
      "- [ ] an open task\n"
      "- [x] a finished one\n"
      "  - a nested item\n"
      "\n"
      "> A quoted line.\n"
      "\n"
      "| column | other |\n"
      "|--------|------:|\n"
      "| value  |    42 |\n"
      "\n"
      "```cpp\n"
      "int answer() { return 42; }\n"
      "```\n"
      "\n");

  QString out;
  out.reserve(approximateBytes + unit.size());
  while(out.size() < approximateBytes) {
    out += unit;
  }
  return out;
}

struct Timing {
  qint64 bestUs = 0;
  qint64 meanUs = 0;
};

Timing timeParses(const QString& markdown, int runs) {
  qint64 best = std::numeric_limits<qint64>::max();
  qint64 total = 0;
  for(int i = 0; i < runs; ++i) {
    QElapsedTimer timer;
    timer.start();
    const MdSourceMap src(markdown);
    const MdAst ast = parse(src);
    const qint64 elapsed = timer.nsecsElapsed() / 1000;
    // Keep the result alive so nothing is optimised away.
    EXPECT_TRUE(ast.isValid());
    best = std::min(best, elapsed);
    total += elapsed;
  }
  return Timing{best, total / runs};
}

// Generous enough to survive a loaded CI runner; tight enough that a
// quadratic regression trips it. A 1 MB parse takes single-digit milliseconds
// locally in a release build.
constexpr qint64 kLargeBudgetMs = 1500;
constexpr qint64 kTypicalBudgetMs = 150;

}  // namespace

TEST(MdBenchTest, ParsesATypicalNoteFastEnoughToRunWhileTyping) {
  const QString markdown = buildDocument(100 * 1024);
  const Timing timing = timeParses(markdown, 5);
  std::printf("[ BENCH    ] 100 KB: best %.2f ms, mean %.2f ms\n", timing.bestUs / 1000.0, timing.meanUs / 1000.0);
  EXPECT_LT(timing.bestUs / 1000, kTypicalBudgetMs) << "A 100 KB note is re-parsed on every typing pause. If this is slow, "
                                                       "make the parse incremental — do not raise the budget.";
}

TEST(MdBenchTest, ParsesALargeBlobWithoutFallingOver) {
  const QString markdown = buildDocument(1024 * 1024);
  const Timing timing = timeParses(markdown, 3);
  std::printf("[ BENCH    ] 1 MB: best %.2f ms, mean %.2f ms\n", timing.bestUs / 1000.0, timing.meanUs / 1000.0);
  EXPECT_LT(timing.bestUs / 1000, kLargeBudgetMs) << "Parse time should be linear in document size. A large jump here "
                                                     "means an accidental quadratic in the anchor or partition pass.";
}

TEST(MdBenchTest, ScalesLinearlyWithDocumentSize) {
  // The partition walks blocks and lines once each; the anchor pass touches
  // every open block per offset. A regression to quadratic would not show up
  // as a failed budget on a fast machine, but it does show up as a bad ratio.
  const Timing small = timeParses(buildDocument(128 * 1024), 3);
  const Timing large = timeParses(buildDocument(1024 * 1024), 3);

  const double ratio = static_cast<double>(large.bestUs) / static_cast<double>(std::max<qint64>(small.bestUs, 1));
  std::printf("[ BENCH    ] 8x the input took %.2fx the time\n", ratio);
  EXPECT_LT(ratio, 24.0) << "Eight times the input should cost roughly eight times the "
                            "time, not the square of it.";
}
