#pragma once

#include <QDateTime>
#include <QString>
#include <QStringList>
#include <QVector>

// "You've seen this before" (APP-159): when what was pasted or typed into
// quick capture, a task description or search looks like an error or a stack
// trace, its gist is looked up in the user's own notes, docs and tasks, and a
// quiet hint names the place it came up before. Local text only, nothing sent
// anywhere, nothing done beyond showing the hint.
//
// Three pure steps, each tested on its own:
//   looksLikeError  — is this an error at all (a heuristic, tuned to stay
//                     quiet on prose that merely mentions "error");
//   signatureOf     — its gist: the error type and the words of its message,
//                     with numbers, addresses, paths and times stripped, so
//                     the same failure on another day or line still matches;
//   bestSeenMatch   — which of the candidates mentions that gist.
namespace heap::safety {

struct ErrorSignature {
  QString type;       // "nullpointerexception", "typeerror", "panic", "error" …
  QStringList words;  // normalized message words, in order, no repeats

  bool isEmpty() const {
    return type.isEmpty() && words.isEmpty();
  }

  bool operator==(const ErrorSignature&) const = default;
};

bool looksLikeError(const QString& text);

ErrorSignature signatureOf(const QString& text);

// Lower-case words of `text` with paths, hex addresses, numbers, times and
// short or common words removed — the vocabulary signatures are compared in.
QStringList normalizedWords(const QString& text);

// How much of `sig` `text` contains, 0..1: 0 when the type is named and absent,
// otherwise the share of the signature's words found among the text's.
double matchScore(const ErrorSignature& sig, const QString& text);

struct SeenCandidate {
  QString kind;  // "note" | "docPage" | "task"
  QString id;
  QString title;
  QString profileId;
  QDateTime when;
  QString text;
};

// The candidate that best matches `sig`, or -1. A match needs the type (when
// there is one) and most of the message words; ties go to the newest.
qsizetype bestSeenMatch(const ErrorSignature& sig, const QVector<SeenCandidate>& candidates);

}  // namespace heap::safety
