// Markdown parser: structured fuzzing.
//
// The parser derives source ranges from offsets md4c happens to report, then
// fills the gaps by reasoning about blank lines and block types. That is
// exactly the kind of logic that holds on hand-written fixtures and falls over
// on input nobody thought of — a fence opened inside a quote inside a list, a
// table delimiter with no table, a heading made of nothing but hashes.
//
// So rather than more fixtures, this generates documents from markdown tokens
// and from raw bytes, and asserts the partition invariant on every one. The
// generator is seeded, so a failure reproduces exactly: the seed is printed
// with the failing document.
//
// Two things are being checked at once. Under an ordinary build: that the
// ranges stay ordered, contiguous, total and lossless. Under the sanitizer
// build CI runs, the same cases also exercise every pointer-arithmetic path in
// the anchor code, which is where a bad offset would show up as a read out of
// bounds rather than as a wrong answer.

#include "MdPartitionCheck.h"

#include <QString>
#include <QStringList>

#include <gtest/gtest.h>

#include <random>

using heap::md::test::checkPartition;
using heap::md::test::partitionFixtures;

namespace {

// Fragments with a history of being awkward: structure that emits no offsets,
// containers that nest, and characters that are markdown in one position and
// text in another.
const QStringList& tokens() {
  static const QStringList kTokens{
      QStringLiteral("# "),        QStringLiteral("## "),       QStringLiteral("###### "),  QStringLiteral("- "),
      QStringLiteral("* "),        QStringLiteral("1. "),       QStringLiteral("- [ ] "),   QStringLiteral("- [x] "),
      QStringLiteral("> "),        QStringLiteral("> > "),      QStringLiteral("```"),      QStringLiteral("```cpp"),
      QStringLiteral("~~~"),       QStringLiteral("---"),       QStringLiteral("***"),      QStringLiteral("==="),
      QStringLiteral("| a | b |"), QStringLiteral("|---|---|"), QStringLiteral("|:-:|"),    QStringLiteral("    "),
      QStringLiteral("\t"),        QStringLiteral("[ref]: /x"), QStringLiteral("[[wiki]]"), QStringLiteral("[a](b)"),
      QStringLiteral("![i](s)"),   QStringLiteral("**b**"),     QStringLiteral("_e_"),      QStringLiteral("~~s~~"),
      QStringLiteral("`c`"),       QStringLiteral("$x$"),       QStringLiteral("$$"),       QStringLiteral("<div>"),
      QStringLiteral("</div>"),    QStringLiteral("&amp;"),     QStringLiteral("text"),     QStringLiteral("слово"),
      QStringLiteral("🙂"),        QStringLiteral("  "),        QStringLiteral(""),         QStringLiteral("\\"),
      QStringLiteral("<!--"),      QStringLiteral("-->"),
  };
  return kTokens;
}

QString buildTokenDocument(std::mt19937& rng) {
  std::uniform_int_distribution<int> lineCount(1, 14);
  std::uniform_int_distribution<int> perLine(0, 4);
  std::uniform_int_distribution<size_t> pick(0, static_cast<size_t>(tokens().size()) - 1);
  std::uniform_int_distribution<int> blank(0, 3);

  QString out;
  const int lines = lineCount(rng);
  for(int i = 0; i < lines; ++i) {
    if(blank(rng) == 0) {
      out += QLatin1Char('\n');
      continue;
    }
    const int pieces = perLine(rng);
    for(int j = 0; j < pieces; ++j) {
      out += tokens().at(static_cast<int>(pick(rng)));
    }
    out += QLatin1Char('\n');
  }
  return out;
}

// Bytes with no structure at all, including control characters and high code
// points. Nothing here is valid markdown; the parser must still answer.
QString buildByteDocument(std::mt19937& rng) {
  std::uniform_int_distribution<int> length(0, 200);
  std::uniform_int_distribution<int> byte(1, 0x2FFF);

  QString out;
  const int size = length(rng);
  out.reserve(size);
  for(int i = 0; i < size; ++i) {
    const int value = byte(rng);
    // Skip the surrogate range: those are not valid on their own and QString
    // would carry an ill-formed pair rather than anything a user could type.
    out += QChar((value >= 0xD800 && value <= 0xDFFF) ? u'?' : static_cast<char16_t>(value));
  }
  return out;
}

// Small edits to a known-good document: the shapes a user actually produces
// while typing, which is when the parser runs most often.
QString mutateFixture(std::mt19937& rng) {
  const QStringList fixtures = partitionFixtures();
  std::uniform_int_distribution<int> pickFixture(0, static_cast<int>(fixtures.size()) - 1);
  QString text = fixtures.at(pickFixture(rng));
  if(text.isEmpty()) {
    return text;
  }

  std::uniform_int_distribution<int> edits(1, 4);
  std::uniform_int_distribution<int> kind(0, 2);
  const int count = edits(rng);
  for(int i = 0; i < count && !text.isEmpty(); ++i) {
    std::uniform_int_distribution<int> at(0, static_cast<int>(text.size()) - 1);
    int pos = at(rng);

    // Never split a surrogate pair. An emoji is two UTF-16 code units, and
    // removing one of them leaves a string that is not valid Unicode at all —
    // it cannot survive a trip through UTF-8, so a round-trip failure would
    // say nothing about the parser. No editor lets a user produce one either.
    if(text.at(pos).isLowSurrogate() && pos > 0 && text.at(pos - 1).isHighSurrogate()) {
      --pos;
    }
    const int width = (text.at(pos).isHighSurrogate() && pos + 1 < text.size()) ? 2 : 1;

    switch(kind(rng)) {
      case 0:
        text.remove(pos, width);
        break;
      case 1: {
        const QStringList& all = tokens();
        std::uniform_int_distribution<int> pickToken(0, static_cast<int>(all.size()) - 1);
        text.insert(pos, all.at(pickToken(rng)));
        break;
      }
      default:
        text.insert(pos, QLatin1Char('\n'));
        break;
    }
  }
  return text;
}

// Keeps the run bounded on CI while still covering a lot of ground: the same
// budget under the sanitizer build takes roughly a second.
constexpr int kCasesPerGenerator = 3000;

void runGenerator(const char* name, QString (*generate)(std::mt19937&), unsigned seed) {
  std::mt19937 rng(seed);
  for(int i = 0; i < kCasesPerGenerator; ++i) {
    const QString document = generate(rng);
    const QString problem = checkPartition(document);
    ASSERT_TRUE(problem.isEmpty()) << name << " case " << i << " (seed " << seed << ")\n"
                                   << "problem: " << problem.toStdString() << "\n"
                                   << "document (escaped): " << heap::md::test::escape(document).toStdString();
  }
}

}  // namespace

TEST(MdFuzzTest, TokenSoupKeepsThePartitionIntact) {
  runGenerator("token", buildTokenDocument, 0x5EEDu);
}

TEST(MdFuzzTest, RandomBytesKeepThePartitionIntact) {
  runGenerator("bytes", buildByteDocument, 0xB17Eu);
}

TEST(MdFuzzTest, MutatedFixturesKeepThePartitionIntact) {
  runGenerator("mutate", mutateFixture, 0xED17u);
}
