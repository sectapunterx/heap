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

// ── Audit 2026-09-30 ──

TEST(NoteGraph, ANoteHeadingLinkResolvesAcrossNotes) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Diary")),
                            note(QStringLiteral("n2"), QStringLiteral("Standup"), QStringLiteral("# Standup\n\n## Risks\n"))};
  const LinkTarget t = resolveLink(QStringLiteral("Standup#Risks"), notes, QStringLiteral("n1"));
  EXPECT_EQ(t.kind, LinkTarget::HeadingRef);
  EXPECT_EQ(t.noteId, QStringLiteral("n2"));
  EXPECT_EQ(t.heading, QStringLiteral("Risks"));
  // A heading that is not there still opens the note.
  EXPECT_EQ(resolveLink(QStringLiteral("Standup#Nope"), notes, QStringLiteral("n1")).kind, LinkTarget::NoteRef);
}

TEST(NoteGraph, CodeCommentsAndTicketsAreNotHeadings) {
  const QVector<Note> notes{
      note(QStringLiteral("n1"), QStringLiteral("Ops"), QStringLiteral("```bash\n# restart\n```\n#HEAP-12 is blocked\n## Deploy\n"))};
  EXPECT_EQ(resolveLink(QStringLiteral("restart"), notes, QStringLiteral("n1")).kind, LinkTarget::Missing);
  EXPECT_EQ(resolveLink(QStringLiteral("HEAP-12 is blocked"), notes, QStringLiteral("n1")).kind, LinkTarget::Missing);
  EXPECT_EQ(resolveLink(QStringLiteral("Deploy"), notes, QStringLiteral("n1")).kind, LinkTarget::HeadingRef);
}

TEST(NoteGraph, ADuplicateTitlePrefersTheLinkingNotesFolder) {
  Note a = note(QStringLiteral("a"), QStringLiteral("Meeting"));
  a.folder = QStringLiteral("x");
  Note b = note(QStringLiteral("b"), QStringLiteral("Meeting"));
  b.folder = QStringLiteral("y");
  Note from = note(QStringLiteral("f"), QStringLiteral("From"));
  from.folder = QStringLiteral("y");
  EXPECT_EQ(resolveLink(QStringLiteral("Meeting"), {a, b, from}, QStringLiteral("f")).noteId, QStringLiteral("b"));
}

TEST(NoteGraph, HeadingAndLabelLinksAreBacklinks) {
  const QVector<Note> notes{note(QStringLiteral("t"), QStringLiteral("Standup")),
                            note(QStringLiteral("o"), QStringLiteral("Other"), QStringLiteral("[[Standup#Risks]]\n[[standup|daily]]"))};
  EXPECT_EQ(backlinksTo(QStringLiteral("t"), notes).size(), 2);
}

TEST(NoteGraph, RetargetingKeepsHeadingsAndLabels) {
  EXPECT_EQ(heap::notes::retargetLinks(
                QStringLiteral("a [[Old]] b [[old#H]] c [[Old|x]] d [[Older]]"), QStringLiteral("Old"), QStringLiteral("New")),
            QStringLiteral("a [[New]] b [[New#H]] c [[New|x]] d [[Older]]"));
}

TEST(NoteGraph, AResolvedLinkIsNotReported) {
  const QVector<Note> notes{note(QStringLiteral("n1"), QStringLiteral("Diary")), note(QStringLiteral("n2"), QStringLiteral("Standup"))};

  EXPECT_TRUE(unresolvedLinksIn(QStringLiteral("see [[Standup]]"), notes, QStringLiteral("n1")).isEmpty());
}

// ── KNOW-6 (audit 2026-09-30): titles with '#' and '|' ──

TEST(NoteGraph, Know6_ATitleWithAHashOrBarIsLinkable) {
  const QVector<Note> notes{note(QStringLiteral("c"), QStringLiteral("C# basics")),
                            note(QStringLiteral("ab"), QStringLiteral("A|B options"), QStringLiteral("# Pros\n")),
                            note(QStringLiteral("f"), QStringLiteral("From"))};
  const QString from = QStringLiteral("f");
  // Escaped, as autocomplete and rename write it.
  EXPECT_EQ(resolveLink(QStringLiteral("C\\# basics"), notes, from).noteId, QStringLiteral("c"));
  EXPECT_EQ(resolveLink(QStringLiteral("A\\|B options"), notes, from).noteId, QStringLiteral("ab"));
  // Typed by hand, and as md4c hands the preview's target over (unescaped).
  EXPECT_EQ(resolveLink(QStringLiteral("C# basics"), notes, from).noteId, QStringLiteral("c"));
  EXPECT_EQ(resolveLink(QStringLiteral("A|B options"), notes, from).noteId, QStringLiteral("ab"));
  // With a label and a heading after the escaped name.
  EXPECT_EQ(resolveLink(QStringLiteral("C\\# basics|the intro"), notes, from).noteId, QStringLiteral("c"));
  const LinkTarget h = resolveLink(QStringLiteral("A\\|B options#Pros|why"), notes, from);
  EXPECT_EQ(h.kind, LinkTarget::HeadingRef);
  EXPECT_EQ(h.noteId, QStringLiteral("ab"));
  EXPECT_EQ(h.heading, QStringLiteral("Pros"));
  EXPECT_TRUE(unresolvedLinksIn(QStringLiteral("[[C\\# basics]] [[A\\|B options]] [[C# basics]]"), notes, from).isEmpty());
}

TEST(NoteGraph, Know6_OrdinaryHeadingAndLabelLinksStillSplit) {
  const QVector<Note> notes{note(QStringLiteral("s"), QStringLiteral("Standup"), QStringLiteral("## Risks\n")),
                            note(QStringLiteral("f"), QStringLiteral("From"), QStringLiteral("# C# notes\n"))};
  const LinkTarget t = resolveLink(QStringLiteral("Standup#Risks|daily"), notes, QStringLiteral("f"));
  EXPECT_EQ(t.kind, LinkTarget::HeadingRef);
  EXPECT_EQ(t.noteId, QStringLiteral("s"));
  // A heading of the linking note with a '#' in it.
  const LinkTarget own = resolveLink(QStringLiteral("C\\# notes"), notes, QStringLiteral("f"));
  EXPECT_EQ(own.kind, LinkTarget::HeadingRef);
  EXPECT_EQ(own.heading, QStringLiteral("C# notes"));
}

TEST(NoteGraph, Know6_BacklinksFindEscapedAndRawSpellings) {
  const QVector<Note> notes{
      note(QStringLiteral("c"), QStringLiteral("C# basics")),
      note(QStringLiteral("c0"), QStringLiteral("C")),
      note(QStringLiteral("o"), QStringLiteral("Other"), QStringLiteral("[[C\\# basics]]\n[[C# basics|x]]\n[[C#Intro]]"))};
  EXPECT_EQ(backlinksTo(QStringLiteral("c"), notes).size(), 2);
  // [[C#Intro]] is the heading Intro of the note called C.
  EXPECT_EQ(backlinksTo(QStringLiteral("c0"), notes).size(), 1);
}

TEST(NoteGraph, Know6_RenameWritesAnEscapedNameThatRoundTrips) {
  const QString body = QStringLiteral("a [[Plain target]] b [[plain target#H|lbl]] c [[Plain target|x]]");
  const QString renamed = heap::notes::retargetLinks(body, QStringLiteral("Plain target"), QStringLiteral("Topic #1"));
  EXPECT_EQ(renamed, QStringLiteral("a [[Topic \\#1]] b [[Topic \\#1#H|lbl]] c [[Topic \\#1|x]]"));
  const QVector<Note> notes{note(QStringLiteral("t"), QStringLiteral("Topic #1"), QStringLiteral("# H\n")),
                            note(QStringLiteral("o"), QStringLiteral("Other"), renamed)};
  EXPECT_TRUE(unresolvedLinksIn(renamed, notes, QStringLiteral("o")).isEmpty());
  EXPECT_EQ(backlinksTo(QStringLiteral("t"), notes).size(), 1);  // all on one line
  // Renamed again, the escaped links are found and rewritten.
  EXPECT_EQ(heap::notes::retargetLinks(renamed, QStringLiteral("Topic #1"), QStringLiteral("A|B")),
            QStringLiteral("a [[A\\|B]] b [[A\\|B#H|lbl]] c [[A\\|B|x]]"));
}

TEST(NoteGraph, Know6_EscapingIsReversible) {
  for(const QString& title :
      {QStringLiteral("C# basics"), QStringLiteral("A|B"), QStringLiteral("dir\\"), QStringLiteral("a\\#b"), QStringLiteral("plain")}) {
    const QString escaped = heap::notes::escapeLinkName(title);
    EXPECT_EQ(heap::notes::noteNameOf(escaped), title) << escaped.toStdString();
    EXPECT_TRUE(heap::notes::headingPartOf(escaped).isEmpty()) << escaped.toStdString();
  }
}
