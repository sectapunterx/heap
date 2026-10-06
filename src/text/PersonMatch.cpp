#include "text/PersonMatch.h"
#include "text/TaskTextUtils.h"

#include <QStringList>

#include <algorithm>

namespace heap::text {

namespace {

// One word, lowercased and transliterated, with the spellings a Russian name
// takes in Latin folded together, so "Юлия", "yulia", "iuliia" and "julia"
// are one key. Both sides of a comparison go through it, so a fold that is
// lossy ("ts" and "ц" both become "c") only ever makes more things equal.
QString fold(QStringView word) {
  QString a = asciiFold(word);
  if(a.isEmpty()) {
    // A script with no transliteration (CJK, Greek...): the word as written.
    for(const QChar c : word) {
      if(c.isLetterOrNumber()) {
        a += c.toLower();
      }
    }
    return a;
  }
  a.replace(QLatin1String("shch"), QLatin1String("sch"));
  a.replace(QLatin1String("kh"), QLatin1String("h"));
  a.replace(QLatin1String("ts"), QLatin1String("c"));
  a.replace(QLatin1Char('x'), QLatin1String("ks"));
  a.replace(QLatin1Char('y'), QLatin1Char('i'));
  a.replace(QLatin1Char('j'), QLatin1Char('i'));
  // "Валерий" -> "valerii", "Мария" -> "mariia": one i, as "maria" has.
  QString out;
  out.reserve(a.size());
  for(const QChar c : a) {
    if(c != QLatin1Char('i') || out.isEmpty() || out.back() != QLatin1Char('i')) {
      out += c;
    }
  }
  // "Yevgeny" for "Евгений": a word-initial "ye" is the Cyrillic е.
  if(out.startsWith(QLatin1String("ie"))) {
    out.remove(0, 1);
  }
  return out;
}

bool isSeparator(QChar c) {
  return c.isSpace() || c == QLatin1Char('.') || c == QLatin1Char('_') || c == QLatin1Char('-') || c == QLatin1Char('@');
}

// Folded words of `s`, split on whitespace and on . _ - (a login's
// separators), empty ones dropped. "Олег Т." -> {"oleg", "t"}.
QStringList foldedWords(QStringView s) {
  QStringList out;
  qsizetype start = -1;
  for(qsizetype i = 0; i <= s.size(); ++i) {
    const bool sep = i == s.size() || isSeparator(s.at(i));
    if(sep) {
      if(start >= 0) {
        const QString w = fold(s.mid(start, i - start));
        if(!w.isEmpty()) {
          out << w;
        }
        start = -1;
      }
    } else if(start < 0) {
      start = i;
    }
  }
  return out;
}

// Can each query word start a different name word? Names have a handful of
// words, so trying every assignment costs nothing.
bool wordsPrefix(const QStringList& q, qsizetype qi, const QStringList& words, QList<bool>& used) {
  if(qi == q.size()) {
    return true;
  }
  for(qsizetype w = 0; w < words.size(); ++w) {
    if(!used[w] && words[w].startsWith(q[qi])) {
      used[w] = true;
      if(wordsPrefix(q, qi + 1, words, used)) {
        return true;
      }
      used[w] = false;
    }
  }
  return false;
}

}  // namespace

int personMatchRank(QStringView query, QStringView name, QStringView id) {
  const QString q = query.trimmed().toString().toLower();
  if(q.isEmpty()) {
    return PersonRank::Substring;
  }
  int rank = PersonRank::NoMatch;
  const QString idLower = id.toString().toLower();
  if(!idLower.isEmpty()) {
    if(q == idLower) {
      return PersonRank::ExactId;
    }
    if(idLower.startsWith(q)) {
      rank = PersonRank::IdPrefix;
    }
  }

  const QStringList qWords = foldedWords(q);
  const QString qKey = qWords.join(QString());
  const QStringList words = foldedWords(name);
  if(qKey.isEmpty()) {
    return std::max(rank, name.toString().toLower().contains(q) ? PersonRank::Substring : PersonRank::NoMatch);
  }

  // The logins a name stands for, separators dropped: initial + surname
  // either way round, both names either way round, each name alone. A
  // one-letter word ("Т." in "Олег Т.") is no login on its own.
  QStringList forms;
  if(words.size() == 1) {
    forms << words.first();
  } else if(words.size() >= 2) {
    const QString& f = words.first();
    const QString& l = words.last();
    forms << f.left(1) + l << l + f.left(1) << f + l << l + f;
    if(l.size() >= 2) {
      forms << l;
    }
    if(f.size() >= 2) {
      forms << f;
    }
  }
  const QString idKey = foldedWords(id).join(QString());
  if(!idKey.isEmpty()) {
    forms << idKey;
  }
  for(const QString& form : std::as_const(forms)) {
    if(form == qKey) {
      return PersonRank::ExactHandle;
    }
    if(form.startsWith(qKey)) {
      rank = std::max(rank, PersonRank::HandlePrefix);
    }
  }

  if(rank < PersonRank::WordPrefix && qWords.size() <= words.size()) {
    QList<bool> used(words.size(), false);
    if(wordsPrefix(qWords, 0, words, used)) {
      rank = PersonRank::WordPrefix;
    }
  }
  if(rank < PersonRank::Substring && (words.join(QString()).contains(qKey) || name.toString().toLower().contains(q))) {
    rank = PersonRank::Substring;
  }
  return rank;
}

}  // namespace heap::text
