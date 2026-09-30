// Notes as a folder of .md files.
//
// Notes that only exist inside one application's state file are notes people
// keep somewhere else as well. Markdown on disk — one file per note,
// directories for folders — is what Obsidian, Foam, Dendron and a shell prompt
// all already agree on.
//
// The decisions worth arguing about are all in the naming: what a note is
// called when its title contains a slash, what happens when two notes want the
// same filename, and which files in a vault are not notes at all.

#include "notes/MdVault.h"

#include <gtest/gtest.h>

using heap::notes::exportVault;
using heap::notes::importFile;
using heap::notes::isIgnoredPath;
using heap::notes::VaultFile;

namespace {

Note note(const QString& title, const QString& folder = QString(), const QString& body = QStringLiteral("body")) {
  Note n;
  n.id = QStringLiteral("n-") + title;
  n.title = title;
  n.folder = folder;
  n.body = body;
  n.created = QDateTime(QDate(2026, 1, 2), QTime(3, 4));
  n.updated = QDateTime(QDate(2026, 5, 6), QTime(7, 8));
  return n;
}

QStringList pathsOf(const QVector<VaultFile>& files) {
  QStringList out;
  for(const VaultFile& f : files) {
    out << f.path;
  }
  return out;
}

}  // namespace

// ── Naming ──

TEST(MdVault, ANoteBecomesAMarkdownFile) {
  EXPECT_EQ(pathsOf(exportVault({note(QStringLiteral("Standup"))})), QStringList{QStringLiteral("Standup.md")});
}

TEST(MdVault, AFolderBecomesADirectory) {
  const auto files = exportVault({note(QStringLiteral("Standup"), QStringLiteral("meetings/2026"))});

  EXPECT_EQ(pathsOf(files), QStringList{QStringLiteral("meetings/2026/Standup.md")});
}

// A title with a slash in it would otherwise become a directory nobody asked
// for; one with a colon cannot be created on Windows at all.
TEST(MdVault, ForbiddenCharactersLeaveTheFileName) {
  const auto files = exportVault({note(QStringLiteral("Q3: plan / draft"))});

  ASSERT_EQ(files.size(), 1);
  EXPECT_FALSE(files.at(0).path.contains(QLatin1Char(':')));
  EXPECT_EQ(files.at(0).path.count(QLatin1Char('/')), 0);
}

// A trailing dot or space is legal in a QString and not on Windows.
TEST(MdVault, ATrailingDotIsTrimmed) {
  const auto files = exportVault({note(QStringLiteral("Plan."))});

  EXPECT_EQ(files.at(0).path, QStringLiteral("Plan.md"));
}

TEST(MdVault, AnUntitledNoteStillGetsAFileName) {
  Note n = note(QString());
  n.title.clear();

  const auto files = exportVault({n});

  ASSERT_EQ(files.size(), 1);
  EXPECT_FALSE(files.at(0).path.isEmpty());
  EXPECT_TRUE(files.at(0).path.endsWith(QStringLiteral(".md")));
}

// A vault is a filesystem: two notes called the same thing in the same folder
// cannot both be that file, and the alternative to a suffix is one of them
// silently overwriting the other.
TEST(MdVault, TwoNotesWithOneTitleGetDistinctFiles) {
  const auto files = exportVault({note(QStringLiteral("Meeting")), note(QStringLiteral("Meeting"))});

  ASSERT_EQ(files.size(), 2);
  EXPECT_NE(files.at(0).path, files.at(1).path);
}

// Same title in different folders is not a collision.
TEST(MdVault, TheSameTitleInTwoFoldersKeepsBothNames) {
  const auto files =
      exportVault({note(QStringLiteral("Meeting"), QStringLiteral("a")), note(QStringLiteral("Meeting"), QStringLiteral("b"))});

  EXPECT_EQ(pathsOf(files), (QStringList{QStringLiteral("a/Meeting.md"), QStringLiteral("b/Meeting.md")}));
}

// Filesystems that ignore case would still collide.
TEST(MdVault, ACaseOnlyDifferenceIsTreatedAsACollision) {
  const auto files = exportVault({note(QStringLiteral("Meeting")), note(QStringLiteral("meeting"))});

  EXPECT_NE(files.at(0).path.toLower(), files.at(1).path.toLower());
}

// A folder is a name, not a path expression: ".." would write outside the vault.
TEST(MdVault, AFolderCannotEscapeTheVault) {
  const auto files = exportVault({note(QStringLiteral("Escape"), QStringLiteral("../../etc"))});

  EXPECT_FALSE(files.at(0).path.contains(QStringLiteral("..")));
}

TEST(MdVault, EmptyFolderSegmentsAreDropped) {
  const auto files = exportVault({note(QStringLiteral("N"), QStringLiteral("a//b/"))});

  EXPECT_EQ(files.at(0).path, QStringLiteral("a/b/N.md"));
}

// ── Frontmatter ──

TEST(MdVault, AFileStartsWithItsFrontmatter) {
  const auto files = exportVault({note(QStringLiteral("Standup"))});

  EXPECT_TRUE(files.at(0).contents.startsWith(QStringLiteral("---\n")));
  EXPECT_TRUE(files.at(0).contents.contains(QStringLiteral("title: \"Standup\"")));
}

// Only what heap actually holds. A key invented here would be lost on the next
// round trip and read as heap corrupting the file.
TEST(MdVault, UnpinnedNotesCarryNoPinnedKey) {
  const auto files = exportVault({note(QStringLiteral("Standup"))});

  EXPECT_FALSE(files.at(0).contents.contains(QStringLiteral("pinned:")));
}

TEST(MdVault, AQuoteInATitleIsEscaped) {
  const auto files = exportVault({note(QStringLiteral("The \"big\" plan"))});

  const Note back = importFile(QStringLiteral("x.md"), files.at(0).contents);
  EXPECT_EQ(back.title, QStringLiteral("The \"big\" plan"));
}

// ── Reading ──

TEST(MdVault, TheFileNameBecomesTheTitleWhenThereIsNoFrontmatter) {
  const Note n = importFile(QStringLiteral("Standup.md"), QStringLiteral("just a body"));

  EXPECT_EQ(n.title, QStringLiteral("Standup"));
  EXPECT_EQ(n.body, QStringLiteral("just a body"));
}

TEST(MdVault, TheDirectoryBecomesTheFolder) {
  const Note n = importFile(QStringLiteral("meetings/2026/Standup.md"), QStringLiteral("body"));

  EXPECT_EQ(n.folder, QStringLiteral("meetings/2026"));
}

// The file may have been renamed on disk while the note inside kept its name.
TEST(MdVault, FrontmatterBeatsTheFileName) {
  const Note n = importFile(QStringLiteral("whatever.md"), QStringLiteral("---\ntitle: \"Real title\"\n---\n\nbody"));

  EXPECT_EQ(n.title, QStringLiteral("Real title"));
}

TEST(MdVault, FrontmatterIsNotPartOfTheBody) {
  const Note n = importFile(QStringLiteral("x.md"), QStringLiteral("---\ntitle: \"T\"\n---\n\nthe body"));

  EXPECT_EQ(n.body, QStringLiteral("the body"));
}

TEST(MdVault, PinnedAndDatesAreRead) {
  const Note n =
      importFile(QStringLiteral("x.md"), QStringLiteral("---\ntitle: \"T\"\npinned: true\ncreated: 2026-01-02T03:04:00\n---\n\nbody"));

  EXPECT_TRUE(n.pinned);
  EXPECT_EQ(n.created.date(), QDate(2026, 1, 2));
}

// A --- further down is a horizontal rule, not a frontmatter fence: treating it
// as one would eat the first half of the note.
TEST(MdVault, AHorizontalRuleIsNotFrontmatter) {
  const QString body = QStringLiteral("Some text\n\n---\n\nmore text");

  const Note n = importFile(QStringLiteral("x.md"), body);

  EXPECT_EQ(n.body, body);
  EXPECT_EQ(n.title, QStringLiteral("x"));
}

// An unterminated fence is a broken file, and eating the whole note would be
// worse than showing the mess.
TEST(MdVault, AnUnterminatedFenceLeavesTheBodyAlone) {
  const QString body = QStringLiteral("---\ntitle: \"never closed\"\n\nstill going");

  const Note n = importFile(QStringLiteral("x.md"), body);

  EXPECT_EQ(n.body, body);
}

TEST(MdVault, WindowsLineEndingsAreUnderstood) {
  const Note n = importFile(QStringLiteral("x.md"), QStringLiteral("---\r\ntitle: \"T\"\r\n---\r\n\r\nbody"));

  EXPECT_EQ(n.title, QStringLiteral("T"));
  EXPECT_FALSE(n.body.startsWith(QStringLiteral("---")));
}

TEST(MdVault, AMarkdownExtensionIsAlsoAccepted) {
  const Note n = importFile(QStringLiteral("Standup.markdown"), QStringLiteral("body"));

  EXPECT_EQ(n.title, QStringLiteral("Standup"));
}

// A note with no dates still has to sort somewhere.
TEST(MdVault, AFileWithNoDatesGetsThem) {
  const Note n = importFile(QStringLiteral("x.md"), QStringLiteral("body"));

  EXPECT_TRUE(n.created.isValid());
  EXPECT_TRUE(n.updated.isValid());
}

TEST(MdVault, AnEmptyFileIsStillANote) {
  const Note n = importFile(QStringLiteral("Empty.md"), QString());

  EXPECT_EQ(n.title, QStringLiteral("Empty"));
  EXPECT_TRUE(n.body.isEmpty());
}

// ── What is not a note ──

// Obsidian keeps its settings in .obsidian and its deletions in .trash;
// importing either fills the list with configuration and things the user
// already threw away.
TEST(MdVault, DotDirectoriesAreIgnored) {
  EXPECT_TRUE(isIgnoredPath(QStringLiteral(".obsidian/workspace.json")));
  EXPECT_TRUE(isIgnoredPath(QStringLiteral(".trash/deleted.md")));
  EXPECT_TRUE(isIgnoredPath(QStringLiteral("notes/.git/config")));
  EXPECT_TRUE(isIgnoredPath(QStringLiteral(".hidden.md")));
}

TEST(MdVault, OrdinaryPathsAreNotIgnored) {
  EXPECT_FALSE(isIgnoredPath(QStringLiteral("Standup.md")));
  EXPECT_FALSE(isIgnoredPath(QStringLiteral("meetings/2026/Standup.md")));
}

// ── Round trips ──

TEST(MdVault, ANoteSurvivesARoundTrip) {
  const Note original = note(QStringLiteral("Standup"), QStringLiteral("meetings"), QStringLiteral("# Standup\n\nbody\n"));

  const auto files = exportVault({original});
  const Note back = importFile(files.at(0).path, files.at(0).contents);

  EXPECT_EQ(back.title, original.title);
  EXPECT_EQ(back.folder, original.folder);
  EXPECT_EQ(back.body, original.body);
  EXPECT_EQ(back.created, original.created);
  EXPECT_EQ(back.updated, original.updated);
}

TEST(MdVault, APinnedNoteSurvivesARoundTrip) {
  Note original = note(QStringLiteral("Important"));
  original.pinned = true;

  const auto files = exportVault({original});

  EXPECT_TRUE(importFile(files.at(0).path, files.at(0).contents).pinned);
}

// The body is the thing people care about; not one character of it may move.
TEST(MdVault, ABodyWithItsOwnDashesSurvives) {
  const Note original = note(QStringLiteral("Tricky"), QString(), QStringLiteral("intro\n\n---\n\noutro\n"));

  const auto files = exportVault({original});

  EXPECT_EQ(importFile(files.at(0).path, files.at(0).contents).body, original.body);
}

TEST(MdVault, AnEmptyVaultExportsNothing) {
  EXPECT_TRUE(exportVault({}).isEmpty());
}

// ── Audit 2026-09-30: round trips that lost or renamed things ──

TEST(MdVault, TheIdTravelsInTheFrontmatter) {
  const auto files = exportVault({note(QStringLiteral("Meeting"))});
  EXPECT_EQ(importFile(files.at(0).path, files.at(0).contents).id, QStringLiteral("n-Meeting"));
}

TEST(MdVault, ABodyStartingWithABlankLineKeepsIt) {
  const Note original = note(QStringLiteral("Gap"), QString(), QStringLiteral("\nafter a blank line\n"));
  const auto files = exportVault({original});
  EXPECT_EQ(importFile(files.at(0).path, files.at(0).contents).body, original.body);
}

TEST(MdVault, ASanitisedFolderComesBackUnderItsRealName) {
  const Note original = note(QStringLiteral("Plan"), QStringLiteral("Q3: plan"));
  const auto files = exportVault({original});
  EXPECT_EQ(files.at(0).path, QStringLiteral("Q3 plan/Plan.md"));
  EXPECT_EQ(importFile(files.at(0).path, files.at(0).contents).folder, QStringLiteral("Q3: plan"));
}

TEST(MdVault, AFileMovedOnDiskKeepsItsNewFolder) {
  const auto files = exportVault({note(QStringLiteral("Plan"), QStringLiteral("Q3: plan"))});
  EXPECT_EQ(importFile(QStringLiteral("archive/Plan.md"), files.at(0).contents).folder, QStringLiteral("archive"));
}

TEST(MdVault, WindowsReservedNamesAreNotUsedAsFileNames) {
  const auto files = exportVault({note(QStringLiteral("CON")), note(QStringLiteral("nul.txt")), note(QStringLiteral("LPT1"))});
  for(const VaultFile& f : files) {
    EXPECT_FALSE(heap::notes::detail::isReservedWindowsName(f.path.chopped(3))) << f.path.toStdString();
  }
}

TEST(MdVault, ForeignFrontmatterIsKeptAndWrittenBack) {
  const QString file = QStringLiteral("---\ntags:\n  - work\n  - q3\naliases: [Plan B]\ntitle: Plan\n---\nbody");
  const Note n = importFile(QStringLiteral("Plan.md"), file);
  EXPECT_EQ(n.title, QStringLiteral("Plan"));
  EXPECT_EQ(n.body, QStringLiteral("body"));
  EXPECT_TRUE(n.frontmatter.contains(QStringLiteral("  - q3")));
  EXPECT_TRUE(n.frontmatter.contains(QStringLiteral("aliases: [Plan B]")));
  const auto files = exportVault({n});
  EXPECT_TRUE(files.at(0).contents.contains(QStringLiteral("tags:\n  - work\n  - q3")));
}

TEST(MdVault, Latin1BytesAreNotMangled) {
  const QByteArray latin1("caf\xE9 cr\xE8me", 10);
  EXPECT_EQ(heap::notes::decodeVaultBytes(latin1), QString::fromUtf8("café crème"));
  EXPECT_EQ(heap::notes::decodeVaultBytes(QByteArray("\xEF\xBB\xBFhi")), QStringLiteral("hi"));
}

TEST(MdVault, BinaryBytesAreRefused) {
  bool binary = false;
  heap::notes::decodeVaultBytes(QByteArray("PK\x03\x04\0\0", 6), &binary);
  EXPECT_TRUE(binary);
}

namespace {

using heap::notes::planImport;
using heap::notes::VaultAction;
using heap::notes::VaultSource;

std::function<QString()> counterIds() {
  auto n = std::make_shared<int>(0);
  return [n]() {
    return QStringLiteral("fresh-%1").arg(++*n);
  };
}

}  // namespace

// Three notes titled Meeting / Meeting / meeting go out as three files and
// must come back as three notes, each with its own body.
TEST(MdVaultPlan, DuplicateTitlesSurviveTheRoundTrip) {
  QVector<Note> notes = {note(QStringLiteral("Meeting"), {}, QStringLiteral("one")),
                         note(QStringLiteral("Meeting"), {}, QStringLiteral("two")),
                         note(QStringLiteral("meeting"), {}, QStringLiteral("three"))};
  notes[1].id = QStringLiteral("n-2");
  notes[2].id = QStringLiteral("n-3");
  QVector<VaultSource> sources;
  for(const VaultFile& f : exportVault(notes)) {
    sources.append({f.path, f.contents});
  }
  const auto plan = planImport({}, sources, counterIds(), QStringLiteral(" (copy)"));
  ASSERT_EQ(plan.size(), 3);
  QStringList bodies;
  QSet<QString> ids;
  for(const auto& it : plan) {
    EXPECT_EQ(it.action, VaultAction::Create);
    bodies << it.note.body;
    ids.insert(it.note.id);
  }
  bodies.sort();
  EXPECT_EQ(bodies, (QStringList{QStringLiteral("one"), QStringLiteral("three"), QStringLiteral("two")}));
  EXPECT_EQ(ids.size(), 3);
}

TEST(MdVaultPlan, TwoFilesWithOneFrontmatterTitleStayTwoNotes) {
  const QVector<VaultSource> sources = {{QStringLiteral("dup/Meeting.md"), QStringLiteral("---\ntitle: Meeting\n---\nA")},
                                        {QStringLiteral("dup/Meeting 2.md"), QStringLiteral("---\ntitle: Meeting\n---\nB")}};
  const auto first = planImport({}, sources, counterIds(), {});
  ASSERT_EQ(first.size(), 2);
  EXPECT_EQ(first.at(0).note.body, QStringLiteral("A"));
  EXPECT_EQ(first.at(1).note.body, QStringLiteral("B"));

  // Imported, then imported again: each file finds its own note by path.
  const QVector<Note> existing = {first.at(0).note, first.at(1).note};
  const auto again = planImport(existing, sources, counterIds(), {});
  EXPECT_EQ(again.at(0).action, VaultAction::Unchanged);
  EXPECT_EQ(again.at(1).action, VaultAction::Unchanged);
  EXPECT_EQ(again.at(0).note.id, existing.at(0).id);
  EXPECT_EQ(again.at(1).note.id, existing.at(1).id);
}

TEST(MdVaultPlan, AFileChangedOnDiskOnlyUpdatesTheNote) {
  const auto first = planImport({}, {{QStringLiteral("S.md"), QStringLiteral("v1")}}, counterIds(), {});
  const auto again = planImport({first.at(0).note}, {{QStringLiteral("S.md"), QStringLiteral("v2")}}, counterIds(), {});
  ASSERT_EQ(again.size(), 1);
  EXPECT_EQ(again.at(0).action, VaultAction::Update);
  EXPECT_EQ(again.at(0).note.body, QStringLiteral("v2"));
}

TEST(MdVaultPlan, ANoteEditedInHeapIsNotOverwrittenByAnUnchangedFile) {
  auto first = planImport({}, {{QStringLiteral("S.md"), QStringLiteral("v1")}}, counterIds(), {});
  Note edited = first.at(0).note;
  edited.body = QStringLiteral("edited in heap");
  const auto again = planImport({edited}, {{QStringLiteral("S.md"), QStringLiteral("v1")}}, counterIds(), {});
  EXPECT_EQ(again.at(0).action, VaultAction::KeepLocal);
  EXPECT_EQ(again.at(0).note.body, QStringLiteral("edited in heap"));
}

TEST(MdVaultPlan, EditedOnBothSidesKeepsBoth) {
  auto first = planImport({}, {{QStringLiteral("S.md"), QStringLiteral("v1")}}, counterIds(), {});
  Note edited = first.at(0).note;
  edited.body = QStringLiteral("heap side");
  const auto again =
      planImport({edited}, {{QStringLiteral("S.md"), QStringLiteral("disk side")}}, counterIds(), QStringLiteral(" (from disk)"));
  ASSERT_EQ(again.at(0).action, VaultAction::Conflict);
  EXPECT_EQ(again.at(0).note.body, QStringLiteral("heap side"));
  EXPECT_EQ(again.at(0).copy.body, QStringLiteral("disk side"));
  EXPECT_EQ(again.at(0).copy.title, QStringLiteral("S (from disk)"));
  EXPECT_NE(again.at(0).copy.id, again.at(0).note.id);

  // The same file a third time is not another conflict: heap has seen it.
  const auto third =
      planImport({again.at(0).note, again.at(0).copy}, {{QStringLiteral("S.md"), QStringLiteral("disk side")}}, counterIds(), {});
  EXPECT_EQ(third.at(0).action, VaultAction::KeepLocal);
}

// A note that predates vault bookkeeping has no baseline: a differing file
// is a conflict, never a silent overwrite.
TEST(MdVaultPlan, ALegacyNoteWithoutABaselineIsNeverOverwritten) {
  const Note legacy = note(QStringLiteral("Standup"), {}, QStringLiteral("mine"));
  const auto plan =
      planImport({legacy}, {{QStringLiteral("Standup.md"), QStringLiteral("theirs")}}, counterIds(), QStringLiteral(" (from disk)"));
  ASSERT_EQ(plan.size(), 1);
  EXPECT_EQ(plan.at(0).action, VaultAction::Conflict);
  EXPECT_EQ(plan.at(0).note.body, QStringLiteral("mine"));
}
