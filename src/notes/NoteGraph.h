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

// The part of a link target that names a note: "Standup#Risks" and
// "Standup|the daily one" both name Standup.
inline QString noteNameOf(const QString& target) {
  QString t = target;
  const qsizetype bar = t.indexOf(QLatin1Char('|'));
  if(bar >= 0) {
    t = t.left(bar);
  }
  const qsizetype hash = t.indexOf(QLatin1Char('#'));
  if(hash >= 0) {
    t = t.left(hash);
  }
  return t.trimmed();
}

// The heading part of "Note#Heading", or empty.
inline QString headingPartOf(const QString& target) {
  QString t = target;
  const qsizetype bar = t.indexOf(QLatin1Char('|'));
  if(bar >= 0) {
    t = t.left(bar);
  }
  const qsizetype hash = t.indexOf(QLatin1Char('#'));
  return hash >= 0 ? t.mid(hash + 1).trimmed() : QString();
}

// The ATX headings of a note, skipping fenced code. A line that merely starts
// with '#' is not a heading: "# comment" inside a ```bash fence is code, and
// "#HEAP-12 is blocked" is a ticket — both used to answer [[comment]] links.
inline QStringList headingsOf(const QString& body) {
  static const QRegularExpression heading(QStringLiteral(R"(^ {0,3}#{1,6}[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$)"));
  QStringList out;
  QString fence;
  for(const QString& raw : body.split(QLatin1Char('\n'))) {
    const QString line = raw.endsWith(QLatin1Char('\r')) ? raw.chopped(1) : raw;
    const QString trimmed = line.trimmed();
    if(fence.isEmpty()) {
      if(trimmed.startsWith(QStringLiteral("```")) || trimmed.startsWith(QStringLiteral("~~~"))) {
        fence = trimmed.left(3);
        continue;
      }
    } else {
      if(trimmed.startsWith(fence)) {
        fence.clear();
      }
      continue;
    }
    const auto m = heading.match(line);
    if(m.hasMatch() && !m.captured(1).trimmed().isEmpty()) {
      out << m.captured(1).trimmed();
    }
  }
  return out;
}

// What `target` points at, given every note there is.
//
// `fromNoteId` is the note the link was written in: a bare heading only
// resolves within it, because "see [[Risks]]" in one note should not silently
// jump to a section of an unrelated one. "[[Other#Risks]]" names the note, so
// that one crosses.
//
// Two notes may share a title (an import can bring in both). The one in the
// linking note's own folder wins, then the first — the same answer every time.
inline LinkTarget resolveLink(const QString& target, const QVector<Note>& notes, const QString& fromNoteId) {
  const QString name = detail::normalise(noteNameOf(target));
  const QString headingPart = headingPartOf(target);
  if(name.isEmpty() && headingPart.isEmpty()) {
    return {};
  }

  const Note* from = nullptr;
  for(const Note& n : notes) {
    if(n.id == fromNoteId) {
      from = &n;
      break;
    }
  }

  const auto headingIn = [](const Note& n, const QString& wanted) -> QString {
    const QString needle = detail::normalise(wanted);
    for(const QString& h : headingsOf(n.body)) {
      if(detail::normalise(h) == needle) {
        return h;
      }
    }
    return {};
  };

  if(!name.isEmpty()) {
    // A note, by title. Exact-but-case-insensitive only: a prefix match would
    // make renaming one note silently repoint links that named another.
    const Note* hit = nullptr;
    for(const Note& n : notes) {
      if(detail::normalise(n.title) != name) {
        continue;
      }
      if(hit == nullptr) {
        hit = &n;
      }
      if(from != nullptr && n.folder == from->folder) {
        hit = &n;
        break;
      }
    }
    if(hit != nullptr) {
      if(!headingPart.isEmpty()) {
        const QString h = headingIn(*hit, headingPart);
        if(!h.isEmpty()) {
          return {LinkTarget::HeadingRef, hit->id, h};
        }
      }
      return {LinkTarget::NoteRef, hit->id, QString()};
    }
  }

  // Failing that, a heading in the note the link was written in — the whole
  // target for [[Risks]], the part after '#' for [[#Risks]].
  if(from != nullptr) {
    const QString wanted = name.isEmpty() ? headingPart : noteNameOf(target);
    if(name.isEmpty() || headingPart.isEmpty()) {
      const QString h = headingIn(*from, wanted);
      if(!h.isEmpty()) {
        return {LinkTarget::HeadingRef, from->id, h};
      }
    }
  }

  return {};
}

// Which notes link to `noteId`, and where.
//
// A note does not count as linking to itself: the backlinks panel exists to
// answer "what else refers to this", and listing the note you are reading is
// noise. [[Title#heading]] and [[Title|label]] are links to the note too.
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
    // Cheap reject before splitting a long body into lines.
    if(!n.body.contains(QStringLiteral("[["))) {
      continue;
    }
    const QStringList lines = n.body.split(QLatin1Char('\n'));
    for(int i = 0; i < lines.size(); ++i) {
      auto it = detail::wikiLinkRe().globalMatch(lines.at(i));
      while(it.hasNext()) {
        if(detail::normalise(noteNameOf(it.next().captured(1))) == needle) {
          out.append({n.id, n.title, i + 1, lines.at(i).trimmed()});
          break;  // one entry per line, however many times it is named there
        }
      }
    }
  }
  return out;
}

// Rewrite every link to the note called `oldTitle` so it names `newTitle`,
// keeping any "#heading" and "|label". Returns the new body, or the same one
// when nothing changed. A rename used to leave every link to the note broken.
inline QString retargetLinks(const QString& body, const QString& oldTitle, const QString& newTitle) {
  if(!body.contains(QStringLiteral("[["))) {
    return body;
  }
  const QString needle = detail::normalise(oldTitle);
  QString out;
  qsizetype last = 0;
  auto it = detail::wikiLinkRe().globalMatch(body);
  bool changed = false;
  while(it.hasNext()) {
    const auto m = it.next();
    const QString inner = m.captured(1);
    if(detail::normalise(noteNameOf(inner)) != needle) {
      continue;
    }
    // Keep whatever followed the name: "#heading", "|label".
    qsizetype cut = inner.size();
    const qsizetype bar = inner.indexOf(QLatin1Char('|'));
    const qsizetype hash = inner.indexOf(QLatin1Char('#'));
    if(hash >= 0 && (bar < 0 || hash < bar)) {
      cut = hash;
    } else if(bar >= 0) {
      cut = bar;
    }
    out += body.mid(last, m.capturedStart(1) - last);
    out += newTitle + inner.mid(cut);
    last = m.capturedEnd(1);
    changed = true;
  }
  if(!changed) {
    return body;
  }
  out += body.mid(last);
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
