#include "safety/ErrorSignature.h"

#include <QRegularExpression>
#include <QSet>

#include <cmath>

namespace heap::safety {

namespace {

// A line that is an error on its own: a typed exception or error with its
// message, a Python traceback header, a Go panic, a compiler's "error:", a
// crash signal.
const QRegularExpression& strongRx() {
  static const QRegularExpression rx(
      QStringLiteral(R"((\b[A-Za-z_][\w.$]*(?:Exception|Error)\b\s*[:(])|(^\s*Traceback \(most recent call last\))|(\bpanic:)|)"
                     R"((\b(?:fatal )?error(?:\[[A-Z]?\d+\])?:\s)|(\bsegfault\b|\bsegmentation fault\b|\bSIG(?:SEGV|ABRT|BUS|ILL)\b)|)"
                     R"((\bUnhandled (?:exception|rejection)\b))"),
      QRegularExpression::CaseInsensitiveOption | QRegularExpression::MultilineOption);
  return rx;
}

// Lines that only look like part of one: stack frames, file:line, addresses.
const QRegularExpression& weakRx() {
  static const QRegularExpression rx(
      QStringLiteral(R"((^\s*at\s+\S+.*[:(]\d+)|(^\s*File "[^"]+", line \d+)|(\S+\.[A-Za-z]{1,5}:\d+(?::\d+)?\b)|)"
                     R"((\b0x[0-9a-fA-F]{6,}\b)|(^\s*#\d+\s+0x))"),
      QRegularExpression::MultilineOption);
  return rx;
}

// The type of a typed error: "java.lang.NullPointerException: …" →
// "NullPointerException", "TypeError: …" → "TypeError". The strict form wants
// the colon, so "Exception in thread "main" java.lang.Foo: …" finds Foo; the
// loose one takes a bare "TypeError".
const QRegularExpression& typedRx() {
  static const QRegularExpression rx(QStringLiteral(R"(\b(?:[A-Za-z_][\w$]*\.)*([A-Za-z_][\w$]*(?:Exception|Error))\b\s*[:(]\s*(.*))"));
  return rx;
}

const QRegularExpression& looseTypedRx() {
  static const QRegularExpression rx(QStringLiteral(R"(\b(?:[A-Za-z_][\w$]*\.)*([A-Za-z_][\w$]*(?:Exception|Error))\b\s*(.*))"));
  return rx;
}

const QSet<QString>& stopWords() {
  static const QSet<QString> words = {
      QStringLiteral("the"),  QStringLiteral("and"),    QStringLiteral("for"),    QStringLiteral("not"),  QStringLiteral("was"),
      QStringLiteral("are"),  QStringLiteral("with"),   QStringLiteral("from"),   QStringLiteral("this"), QStringLiteral("that"),
      QStringLiteral("has"),  QStringLiteral("have"),   QStringLiteral("but"),    QStringLiteral("can"),  QStringLiteral("cannot"),
      QStringLiteral("line"), QStringLiteral("file"),   QStringLiteral("error"),  QStringLiteral("at"),   QStringLiteral("in"),
      QStringLiteral("of"),   QStringLiteral("to"),     QStringLiteral("is"),     QStringLiteral("an"),   QStringLiteral("on"),
      QStringLiteral("call"), QStringLiteral("most"),   QStringLiteral("recent"), QStringLiteral("last"), QStringLiteral("traceback"),
      QStringLiteral("при"),  QStringLiteral("для"),    QStringLiteral("это"),    QStringLiteral("что"),  QStringLiteral("как"),
      QStringLiteral("или"),  QStringLiteral("ошибка"),
  };
  return words;
}

}  // namespace

bool looksLikeError(const QString& text) {
  if(text.trimmed().size() < 8) {
    return false;
  }
  if(strongRx().match(text).hasMatch()) {
    return true;
  }
  // Two signs of a trace without a headline: frames, file:line, addresses.
  int weak = 0;
  auto it = weakRx().globalMatch(text);
  while(it.hasNext() && weak < 2) {
    it.next();
    ++weak;
  }
  return weak >= 2;
}

QStringList normalizedWords(const QString& text) {
  QString s = text.toLower();
  // Things that differ between two occurrences of the same failure.
  static const QRegularExpression urls(QStringLiteral(R"(\b[a-z][a-z0-9+.-]*://\S+)"));
  static const QRegularExpression paths(QStringLiteral(R"((?:[a-z]:)?[\w.~-]*[/\\][\w./\\~-]*)"));
  static const QRegularExpression hex(QStringLiteral(R"(\b0x[0-9a-f]+\b|\b[0-9a-f]{7,40}\b)"));
  static const QRegularExpression digits(QStringLiteral(R"(\d+)"));
  s.replace(urls, QStringLiteral(" "));
  s.replace(paths, QStringLiteral(" "));
  s.replace(hex, QStringLiteral(" "));
  s.replace(digits, QStringLiteral(" "));
  static const QRegularExpression nonWord(QStringLiteral(R"([^\p{L}_]+)"));
  QStringList out;
  QSet<QString> seen;
  for(const QString& w : s.split(nonWord, Qt::SkipEmptyParts)) {
    if(w.size() < 3 || stopWords().contains(w) || seen.contains(w)) {
      continue;
    }
    seen.insert(w);
    out << w;
  }
  return out;
}

ErrorSignature signatureOf(const QString& text) {
  ErrorSignature sig;
  if(!looksLikeError(text)) {
    return sig;
  }
  // The headline: the first line that is an error on its own; failing that,
  // the first line with any text.
  const QStringList lines = text.split(QLatin1Char('\n'));
  QString headline;
  for(const QString& l : lines) {
    if(strongRx().match(l).hasMatch()) {
      headline = l;
      break;
    }
  }
  // A Python traceback names the error last: "ValueError: bad value".
  if(headline.trimmed().startsWith(QStringLiteral("Traceback"), Qt::CaseInsensitive)) {
    for(qsizetype i = lines.size() - 1; i >= 0; --i) {
      if(typedRx().match(lines.at(i)).hasMatch()) {
        headline = lines.at(i);
        break;
      }
    }
  }
  if(headline.isEmpty()) {
    for(const QString& l : lines) {
      if(!l.trimmed().isEmpty()) {
        headline = l;
        break;
      }
    }
  }
  QString message = headline;
  QRegularExpressionMatch typed = typedRx().match(headline);
  if(!typed.hasMatch()) {
    typed = looseTypedRx().match(headline);
  }
  if(typed.hasMatch()) {
    sig.type = typed.captured(1).toLower();
    message = typed.captured(2);
  } else {
    static const QRegularExpression keyword(
        QStringLiteral(R"(\b(panic|segfault|segmentation fault|sigsegv|sigabrt|fatal error|error)(?:\[[a-z]?\d+\])?:?\s*(.*))"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch k = keyword.match(headline);
    if(k.hasMatch()) {
      sig.type = k.captured(1).toLower();
      if(sig.type == QLatin1String("segmentation fault") || sig.type == QLatin1String("sigsegv")) {
        sig.type = QStringLiteral("segfault");
      }
      message = k.captured(2);
    }
  }
  sig.words = normalizedWords(message);
  // Enough to tell two failures apart; the tail of a long message is mostly
  // the specifics that change.
  constexpr qsizetype kMaxWords = 12;
  if(sig.words.size() > kMaxWords) {
    sig.words = sig.words.mid(0, kMaxWords);
  }
  return sig;
}

double matchScore(const ErrorSignature& sig, const QString& text) {
  if(sig.isEmpty() || text.isEmpty()) {
    return 0.0;
  }
  if(!sig.type.isEmpty() && !text.contains(sig.type, Qt::CaseInsensitive)) {
    return 0.0;
  }
  if(sig.words.isEmpty()) {
    return 0.5;  // the type alone: something, not much
  }
  const QStringList have = normalizedWords(text);
  const QSet<QString> haveSet(have.cbegin(), have.cend());
  qsizetype found = 0;
  for(const QString& w : sig.words) {
    found += haveSet.contains(w) ? 1 : 0;
  }
  return static_cast<double>(found) / static_cast<double>(sig.words.size());
}

qsizetype bestSeenMatch(const ErrorSignature& sig, const QVector<SeenCandidate>& candidates) {
  if(sig.isEmpty()) {
    return -1;
  }
  // Most of the message, and never on one common word: a two-word message
  // must match both, a longer one at least 60% and three words.
  const qsizetype n = sig.words.size();
  const double need = n <= 2 ? 1.0 : 0.6;
  if(n == 0 && sig.type.isEmpty()) {
    return -1;
  }
  qsizetype best = -1;
  double bestScore = 0.0;
  for(qsizetype i = 0; i < candidates.size(); ++i) {
    const SeenCandidate& c = candidates.at(i);
    const double score = matchScore(sig, c.title + QLatin1Char('\n') + c.text);
    // A bare type ("TypeError" and no message) is too common to say "seen".
    if(n == 0 || score + 1e-9 < need || (n > 2 && (score * static_cast<double>(n)) + 1e-9 < 3.0)) {
      continue;
    }
    const bool better = score > bestScore + 1e-9 || (std::abs(score - bestScore) <= 1e-9 && best >= 0 && c.when.isValid() &&
                                                     (!candidates.at(best).when.isValid() || c.when > candidates.at(best).when));
    if(best < 0 || better) {
      best = i;
      bestScore = score;
    }
  }
  return best;
}

}  // namespace heap::safety
