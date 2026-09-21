#pragma once

#include "Models.h"

#include <QRegularExpression>
#include <QString>
#include <QVector>

// Links between notes.
//
// `[[Target]]` already worked, for one meaning of "target": a heading inside
// the single blob a profile's notes used to be. Now that a profile holds many
// notes, the thing a reader means by [[Standup]] is almost always the note
// called Standup — and following it has to cross from one document to another,
// which the old resolver had no concept of.
//
// Resolution order is note, then heading, then nothing. A note wins because it
// is the coarser and more deliberate thing: somebody who named a note Standup
// meant it, where a heading called Standup may be one of several.
//
// NoteLinks.h stays as it was and still answers the within-one-document
// questions; this answers the across-notes ones.
namespace heap::notes {

struct LinkTarget {
  enum Kind { Missing, NoteRef, HeadingRef };

  Kind kind = Missing;
  // The note to open, for NoteRef.
  QString noteId;
  // The heading text, for HeadingRef — the caller already has the document and
  // can find the offset with NoteLinks::headingOffset().
  QString heading;
};

// One note linking to another.
struct Backlink {
  QString noteId;
  QString noteTitle;
  int line = 0;  // 1-based, in the linking note
  QString text;  // the line it appeared on, trimmed
};

namespace detail {

// [[Target]], the same shape NoteLinks reads. Non-greedy so `[[a]] and [[b]]`
// is two links rather than one running between them.
inline const QRegularExpression& wikiLinkRe() {
  static const QRegularExpression re(QStringLiteral(R"(\[\[([^\]\[]+)\]\])"));
  return re;
}

inline QString normalise(const QString& s) {
  return s.trimmed().toLower();
}

}  // namespace detail

// Every [[target]] in `markdown`, in document order, de-duplicated by the text
// between the brackets.
inline QStringList linkTargetsIn(const QString& markdown) {
  QStringList out;
  QSet<QString> seen;
  auto it = detail::wikiLinkRe().globalMatch(markdown);
  while(it.hasNext()) {
    const QString target = it.next().captured(1).trimmed();
    if(target.isEmpty()) {
      continue;
    }
    const QString key = detail::normalise(target);
    if(!seen.contains(key)) {
      seen.insert(key);
      out << target;
    }
  }
  return out;
}

// What `target` points at, given every note there is.
//
// `fromNoteId` is the note the link was written in: a heading only resolves
// within it, because "see [[Risks]]" in one note should not silently jump to a
// section of an unrelated one.
inline LinkTarget resolveLink(const QString& target, const QVector<Note>& notes, const QString& fromNoteId) {
  const QString needle = detail::normalise(target);
  if(needle.isEmpty()) {
    return {};
  }

  // A note, by title. Exact-but-case-insensitive only: a prefix match would
  // make renaming one note silently repoint links that named another.
  for(const Note& n : notes) {
    if(detail::normalise(n.title) == needle) {
      return {LinkTarget::NoteRef, n.id, QString()};
    }
  }

  // Failing that, a heading in the note the link was written in.
  for(const Note& n : notes) {
    if(n.id != fromNoteId) {
      continue;
    }
    for(const QString& raw : n.body.split(QLatin1Char('\n'))) {
      QString line = raw.trimmed();
      if(!line.startsWith(QLatin1Char('#'))) {
        continue;
      }
      while(line.startsWith(QLatin1Char('#'))) {
        line = line.mid(1);
      }
      if(detail::normalise(line) == needle) {
        return {LinkTarget::HeadingRef, n.id, line.trimmed()};
      }
    }
    break;
  }

  return {};
}

// Which notes link to `noteId`, and where.
//
// A note does not count as linking to itself: the backlinks panel exists to
// answer "what else refers to this", and listing the note you are reading is
// noise.
inline QVector<Backlink> backlinksTo(const QString& noteId, const QVector<Note>& notes) {
  QVector<Backlink> out;
  QString title;
  for(const Note& n : notes) {
    if(n.id == noteId) {
      title = n.title;
      break;
    }
  }
  if(title.trimmed().isEmpty()) {
    return out;
  }
  const QString needle = detail::normalise(title);

  for(const Note& n : notes) {
    if(n.id == noteId) {
      continue;
    }
    const QStringList lines = n.body.split(QLatin1Char('\n'));
    for(int i = 0; i < lines.size(); ++i) {
      auto it = detail::wikiLinkRe().globalMatch(lines.at(i));
      while(it.hasNext()) {
        if(detail::normalise(it.next().captured(1)) == needle) {
          out.append({n.id, n.title, i + 1, lines.at(i).trimmed()});
          break;  // one entry per line, however many times it is named there
        }
      }
    }
  }
  return out;
}

// Targets in `markdown` that no note and no heading answers to.
//
// Worth surfacing rather than leaving as dead text: in a linked set of notes a
// broken link is usually a note somebody meant to write.
inline QStringList unresolvedLinksIn(const QString& markdown, const QVector<Note>& notes, const QString& fromNoteId) {
  QStringList out;
  for(const QString& target : linkTargetsIn(markdown)) {
    if(resolveLink(target, notes, fromNoteId).kind == LinkTarget::Missing) {
      out << target;
    }
  }
  return out;
}

}  // namespace heap::notes
