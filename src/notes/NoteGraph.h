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

// md4c's rule, so the editor and the preview agree: a backslash before ASCII
// punctuation makes it literal. "[[C\# basics]]" names the note "C# basics"
// rather than the heading "basics" of a note called "C".
inline bool isEscapable(QChar c) {
  const char16_t u = c.unicode();
  return (u >= '!' && u <= '/') || (u >= ':' && u <= '@') || (u >= '[' && u <= '`') || (u >= '{' && u <= '~');
}

inline QString unescapeLink(const QString& s) {
  QString out;
  out.reserve(s.size());
  for(qsizetype i = 0; i < s.size(); ++i) {
    if(s.at(i) == QLatin1Char('\\') && i + 1 < s.size() && isEscapable(s.at(i + 1))) {
      ++i;
    }
    out += s.at(i);
  }
  return out;
}

// Where `ch` appears in `s` other than escaped.
inline QVector<qsizetype> unescapedAt(const QString& s, QChar ch) {
  QVector<qsizetype> out;
  for(qsizetype i = 0; i < s.size(); ++i) {
    if(s.at(i) == QLatin1Char('\\') && i + 1 < s.size() && isEscapable(s.at(i + 1))) {
      ++i;
    } else if(s.at(i) == ch) {
      out << i;
    }
  }
  return out;
}

// One way to read the text between [[ and ]]: the note it names, the heading
// after '#', and where the name ends in that text.
struct NameSplit {
  QString name;
  QString heading;
  qsizetype nameEnd = 0;
};

// Every reading of a link target, most literal first.
//
// The whole text comes first, so a note whose title has a '#' or '|' in it is
// found by its title: "[[C# basics]]" typed by hand, and the preview's target,
// which md4c hands over already unescaped. Then the text before each '|' (the
// rest is a label), and within that each '#' (the rest is a heading). The
// caller takes the first reading that names a note.
inline QVector<NameSplit> nameSplits(const QString& inner) {
  QVector<NameSplit> out;
  out.append({unescapeLink(inner).trimmed(), QString(), inner.size()});
  QVector<qsizetype> ends = unescapedAt(inner, QLatin1Char('|'));
  ends << inner.size();
  for(const qsizetype end : ends) {
    const QString pre = inner.left(end);
    if(end != inner.size()) {
      out.append({unescapeLink(pre).trimmed(), QString(), end});
    }
    for(const qsizetype hash : unescapedAt(pre, QLatin1Char('#'))) {
      out.append({unescapeLink(pre.left(hash)).trimmed(), unescapeLink(pre.mid(hash + 1)).trimmed(), hash});
    }
  }
  return out;
}

}  // namespace detail

// A title as it is written inside [[ ]]. '#' and '|' would otherwise start a
// heading and a label, and a backslash before punctuation (or before the
// closing brackets) would escape it, so all three are escaped.
inline QString escapeLinkName(const QString& title) {
  QString out;
  out.reserve(title.size() + 4);
  for(qsizetype i = 0; i < title.size(); ++i) {
    const QChar c = title.at(i);
    if(c == QLatin1Char('#') || c == QLatin1Char('|') ||
       (c == QLatin1Char('\\') && (i + 1 == title.size() || detail::isEscapable(title.at(i + 1))))) {
      out += QLatin1Char('\\');
    }
    out += c;
  }
  return out;
}

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
// "Standup|the daily one" both name Standup. An escaped "\#" or "\|" is part
// of the name.
inline QString noteNameOf(const QString& target) {
  QString t = target;
  const QVector<qsizetype> bars = detail::unescapedAt(t, QLatin1Char('|'));
  if(!bars.isEmpty()) {
    t = t.left(bars.first());
  }
  const QVector<qsizetype> hashes = detail::unescapedAt(t, QLatin1Char('#'));
  if(!hashes.isEmpty()) {
    t = t.left(hashes.first());
  }
  return detail::unescapeLink(t).trimmed();
}

// The heading part of "Note#Heading", or empty.
inline QString headingPartOf(const QString& target) {
  QString t = target;
  const QVector<qsizetype> bars = detail::unescapedAt(t, QLatin1Char('|'));
  if(!bars.isEmpty()) {
    t = t.left(bars.first());
  }
  const QVector<qsizetype> hashes = detail::unescapedAt(t, QLatin1Char('#'));
  return hashes.isEmpty() ? QString() : detail::unescapeLink(t.mid(hashes.first() + 1)).trimmed();
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

  // A note, by title. Exact-but-case-insensitive only: a prefix match would
  // make renaming one note silently repoint links that named another. Each
  // reading of the target in turn, so "C# basics" is the note of that name
  // before it is a heading of a note called "C".
  for(const detail::NameSplit& split : detail::nameSplits(target)) {
    const QString wanted = detail::normalise(split.name);
    if(wanted.isEmpty()) {
      continue;
    }
    const Note* hit = nullptr;
    for(const Note& n : notes) {
      if(detail::normalise(n.title) != wanted) {
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
      if(!split.heading.isEmpty()) {
        const QString h = headingIn(*hit, split.heading);
        if(!h.isEmpty()) {
          return {LinkTarget::HeadingRef, hit->id, h};
        }
      }
      return {LinkTarget::NoteRef, hit->id, QString()};
    }
  }

  // Failing that, a heading in the note the link was written in — the whole
  // target for [[Risks]] (and for [[C# notes]]), the part after '#' for
  // [[#Risks]].
  if(from != nullptr) {
    const QString whole = detail::unescapeLink(target).trimmed();
    if(!whole.isEmpty()) {
      const QString h = headingIn(*from, whole);
      if(!h.isEmpty()) {
        return {LinkTarget::HeadingRef, from->id, h};
      }
    }
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
  QSet<QString> titles;
  for(const Note& n : notes) {
    titles.insert(detail::normalise(n.title));
  }
  // Read the way resolveLink() reads a target: the first reading that is some
  // note's title is the note it names.
  const auto namesIt = [&](const QString& inner) {
    for(const detail::NameSplit& split : detail::nameSplits(inner)) {
      const QString name = detail::normalise(split.name);
      if(!name.isEmpty() && titles.contains(name)) {
        return name == needle;
      }
    }
    return false;
  };

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
        if(namesIt(it.next().captured(1))) {
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
//
// `accept`, when given, sees each link target that names `oldTitle` and says
// whether it is rewritten — see the overload below for why that matters.
template<typename Accept>
inline QString retargetLinks(const QString& body, const QString& oldTitle, const QString& newTitle, Accept accept) {
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
    qsizetype cut = -1;
    for(const detail::NameSplit& split : detail::nameSplits(inner)) {
      if(detail::normalise(split.name) == needle) {
        cut = split.nameEnd;
        break;
      }
    }
    if(cut < 0 || !accept(inner)) {
      continue;
    }
    // Keep whatever followed the name: "#heading", "|label". The new name is
    // escaped, so a rename to "Topic #1" leaves a link that still finds it.
    out += body.mid(last, m.capturedStart(1) - last);
    out += escapeLinkName(newTitle) + inner.mid(cut);
    last = m.capturedEnd(1);
    changed = true;
  }
  if(!changed) {
    return body;
  }
  out += body.mid(last);
  return out;
}

inline QString retargetLinks(const QString& body, const QString& oldTitle, const QString& newTitle) {
  return retargetLinks(body, oldTitle, newTitle, [](const QString&) {
    return true;
  });
}

// Rewrite, in note `fromNoteId`, only the links that resolve to `renamedId`
// (resolved against `notes` as they were before the rename). Two notes can
// share a title in different folders; matching by title alone made renaming
// teamA/Meeting repoint teamB's [[Meeting]] links at teamA's note (KNOW-7,
// audit 2026-09-30).
inline QString retargetLinksTo(const QString& body,
                               const QString& fromNoteId,
                               const QVector<Note>& notes,
                               const QString& renamedId,
                               const QString& oldTitle,
                               const QString& newTitle) {
  return retargetLinks(body, oldTitle, newTitle, [&](const QString& inner) {
    const LinkTarget t = resolveLink(inner, notes, fromNoteId);
    return t.kind != LinkTarget::Missing && t.noteId == renamedId;
  });
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
