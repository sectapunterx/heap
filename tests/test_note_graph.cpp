// Links between notes.
//
// `[[Target]]` already worked for one meaning of "target": a heading inside the
// single blob a profile's notes used to be. Now that a profile holds many
// notes, what a reader means by [[Standup]] is almost always the note called
// Standup, and following it has to cross from one document to another.

#include "notes/NoteGraph.h"

#include <gtest/gtest.h>

using heap::notes::backlinksTo;
using heap::notes::LinkTarget;
using heap::notes::linkTargetsIn;
using heap::notes::resolveLink;
using heap::notes::unresolvedLinksIn;

namespace {

Note note(const QString& id, const QString& title, const QString& body = QString()) {
  Note n;
  n.id = id;
  n.title = title;
  n.body = body;
  return n;
}

}  // namespace

// ── Finding links ──

TEST(NoteGraph, ALinkIsFound) {
  EXPECT_EQ(linkTargetsIn(QStringLiteral("see [[Standup]] for details")), QStringList{QStringLiteral("Standup")});
}

// Non-greedy, or "[[a]] and [[b]]" is one link running between them.
TEST(NoteGraph, TwoLinksOnALineAreTwoLinks) {
  EXPECT_EQ(linkTargetsIn(QStringLiteral("[[a]] and [[b]]")), (QStringList{QStringLiteral("a"), QStringLiteral("b")}));
}

TEST(NoteGraph, TheSameLinkTwiceIsListedOnce) {
  EXPECT_EQ(linkTargetsIn(QStringLiteral("[[a]] then [[a]] again")), QStringList{QStringLiteral("a")});
}

TEST(NoteGraph, CaseDoesNotMakeASecondLink) {
  EXPECT_EQ(linkTargetsIn(QStringLiteral("[[Standup]] and [[standup]]")).size(), 1);
}

TEST(NoteGraph, AnEmptyLinkIsNotALink) {
  EXPECT_TRUE(linkTargetsIn(QStringLiteral("[[]] and [[   ]]")).isEmpty());
}

TEST(NoteGraph, TextWithNoLinksHasNone) {
  EXPECT_TRUE(linkTargetsIn(QStringLiteral("just [some] ordinary [brackets]")).isEmpty());
}

// ── Resolving ──

TEST(NoteGraph, ALinkResolvesToANoteByTitle) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup"))};

  const LinkTarget t = resolveLink(QStringLiteral("Standup"), notes, QStringLiteral("other"));

  EXPECT_EQ(t.kind, LinkTarget::NoteRef);
  EXPECT_EQ(t.noteId, QStringLiteral("n1"));
}

TEST(NoteGraph, ResolvingIgnoresCaseAndSurroundingSpace) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup"))};

  EXPECT_EQ(resolveLink(QStringLiteral("  stand"
                                       "up  "),
                        notes,
                        QString())
                .noteId,
            QStringLiteral("n1"));
}

// A prefix match would make renaming one note silently repoint links that
// named another.
TEST(NoteGraph, APrefixIsNotAMatch) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup notes"))};

  EXPECT_EQ(resolveLink(QStringLiteral("Standup"), notes, QString()).kind, LinkTarget::Missing);
}

// A note is the coarser, more deliberate thing: somebody who named a note
// Standup meant it, where a heading called Standup may be one of several.
TEST(NoteGraph, ANoteBeatsAHeadingOfTheSameName) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup")),
                            note(QStringLiteral("n2"), QStringLiteral("Diary"), QStringLiteral("# Standup\n\nbody"))};

  const LinkTarget t = resolveLink(QStringLiteral("Standup"), notes, QStringLiteral("n2"));

  EXPECT_EQ(t.kind, LinkTarget::NoteRef);
  EXPECT_EQ(t.noteId, QStringLiteral("n1"));
}

TEST(NoteGraph, AHeadingInTheSameNoteResolves) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Diary"), QStringLiteral("## Risks\n\nbody"))};

  const LinkTarget t = resolveLink(QStringLiteral("Risks"), notes, QStringLiteral("n1"));

  EXPECT_EQ(t.kind, LinkTarget::HeadingRef);
  EXPECT_EQ(t.heading, QStringLiteral("Risks"));
}

// "see [[Risks]]" in one note must not jump to a section of an unrelated one.
TEST(NoteGraph, AHeadingInAnotherNoteDoesNotResolve) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("A"), QStringLiteral("## Risks\n\nbody")),
                            note(QStringLiteral("n2"), QStringLiteral("B"), QStringLiteral("see [[Risks]]"))};

  EXPECT_EQ(resolveLink(QStringLiteral("Risks"), notes, QStringLiteral("n2")).kind, LinkTarget::Missing);
}

TEST(NoteGraph, AnUnknownTargetResolvesToNothing) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup"))};

  EXPECT_EQ(resolveLink(QStringLiteral("Nothing here"), notes, QStringLiteral("n1")).kind, LinkTarget::Missing);
}

TEST(NoteGraph, AnEmptyTargetResolvesToNothing) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup"))};

  EXPECT_EQ(resolveLink(QStringLiteral("   "), notes, QStringLiteral("n1")).kind, LinkTarget::Missing);
}

// ── Backlinks ──

TEST(NoteGraph, ALinkingNoteIsABacklink) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup")),
                            note(QStringLiteral("n2"), QStringLiteral("Diary"), QStringLiteral("see [[Standup]]"))};

  const auto back = backlinksTo(QStringLiteral("n1"), notes);

  ASSERT_EQ(back.size(), 1);
  EXPECT_EQ(back.at(0).noteId, QStringLiteral("n2"));
  EXPECT_EQ(back.at(0).noteTitle, QStringLiteral("Diary"));
  EXPECT_EQ(back.at(0).line, 1);
}

TEST(NoteGraph, TheLineNumberAndTextAreReported) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup")),
                            note(QStringLiteral("n2"), QStringLiteral("Diary"), QStringLiteral("first\nsecond\n  see [[Standup]] here"))};

  const auto back = backlinksTo(QStringLiteral("n1"), notes);

  ASSERT_EQ(back.size(), 1);
  EXPECT_EQ(back.at(0).line, 3);
  EXPECT_EQ(back.at(0).text, QStringLiteral("see [[Standup]] here"));
}

// The panel answers "what else refers to this"; listing the note being read is
// noise.
TEST(NoteGraph, ANoteLinkingToItselfIsNotABacklink) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup"), QStringLiteral("see [[Standup]]"))};

  EXPECT_TRUE(backlinksTo(QStringLiteral("n1"), notes).isEmpty());
}

// Two links on one line are one reason to look at that line, not two.
TEST(NoteGraph, ALineNamingTheTargetTwiceIsOneBacklink) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup")),
                            note(QStringLiteral("n2"), QStringLiteral("Diary"), QStringLiteral("[[Standup]] and [[Standup]]"))};

  EXPECT_EQ(backlinksTo(QStringLiteral("n1"), notes).size(), 1);
}

TEST(NoteGraph, TwoLinesInOneNoteAreTwoBacklinks) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup")),
                            note(QStringLiteral("n2"), QStringLiteral("Diary"), QStringLiteral("[[Standup]]\nand later [[Standup]]"))};

  EXPECT_EQ(backlinksTo(QStringLiteral("n1"), notes).size(), 2);
}

TEST(NoteGraph, BacklinksIgnoreCase) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup")),
                            note(QStringLiteral("n2"), QStringLiteral("Diary"), QStringLiteral("see [[standup]]"))};

  EXPECT_EQ(backlinksTo(QStringLiteral("n1"), notes).size(), 1);
}

TEST(NoteGraph, ANoteNobodyLinksToHasNoBacklinks) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Lonely")),
                            note(QStringLiteral("n2"), QStringLiteral("Diary"), QStringLiteral("no links here"))};

  EXPECT_TRUE(backlinksTo(QStringLiteral("n1"), notes).isEmpty());
}

// An untitled note cannot be named, so nothing can link to it — and matching on
// an empty title would otherwise make every link in the vault a backlink.
TEST(NoteGraph, AnUntitledNoteHasNoBacklinks) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QString()),
                            note(QStringLiteral("n2"), QStringLiteral("Diary"), QStringLiteral("see [[something]]"))};

  EXPECT_TRUE(backlinksTo(QStringLiteral("n1"), notes).isEmpty());
}

TEST(NoteGraph, BacklinksForANoteThatDoesNotExistAreEmpty) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Standup"))};

  EXPECT_TRUE(backlinksTo(QStringLiteral("nobody"), notes).isEmpty());
}

// ── Broken links ──

// In a linked set of notes a broken link is usually a note somebody meant to
// write, which is worth surfacing rather than leaving as dead text.
TEST(NoteGraph, AnUnresolvedLinkIsReported) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Diary"))};

  EXPECT_EQ(unresolvedLinksIn(QStringLiteral("see [[Ghost]]"), notes, QStringLiteral("n1")), QStringList{QStringLiteral("Ghost")});
}

TEST(NoteGraph, AResolvedLinkIsNotReported) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Diary")), note(QStringLiteral("n2"), QStringLiteral("Standup"))};

  EXPECT_TRUE(unresolvedLinksIn(QStringLiteral("see [[Standup]]"), notes, QStringLiteral("n1")).isEmpty());
}
