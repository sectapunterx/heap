// Coverage for AppController::appendNoteEntry — the C++ side of the
// Quick-capture Notes popup (Ctrl+Shift+N). Verifies the empty-input
// guard, the first-entry vs subsequent-entry formatting branches, the
// trimming behavior, and the notesStateChanged signal contract.
//
// Runs headless via the same QApplication + offscreen QPA +
// QStandardPaths test-mode boot the selection suite uses, so the tests
// never touch the user's real state.json.

#include "AppController.h"
#include "Models.h"

#include "notes/NoteLinks.h"

#include <QApplication>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QString>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

// The timestamp header lives on its own line as "### YYYY-MM-DD HH:MM".
// Tests compare against this regex instead of hard-coding the current
// clock so the suite stays deterministic even if the minute rolls over
// mid-test.
const QRegularExpression kStampLineRe(QStringLiteral(R"(^### \d{4}-\d{2}-\d{2} \d{2}:\d{2}$)"));

}  // namespace

class NotesAppendTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->setNotesState(QString());
  }

  void TearDown() override {
    app_.reset();
  }

  std::unique_ptr<AppController> app_;
};

// ─── empty-input guard ───────────────────────────────────────────────

TEST_F(NotesAppendTest, EmptyTextIsNoOp) {
  app_->setNotesState(QStringLiteral("prev content"));
  QSignalSpy spy(app_.get(), &AppController::notesStateChanged);

  app_->appendNoteEntry(QString());

  EXPECT_EQ(app_->notesState(), QStringLiteral("prev content"));
  EXPECT_EQ(spy.count(), 0);
}

TEST_F(NotesAppendTest, WhitespaceOnlyTextIsNoOp) {
  app_->setNotesState(QStringLiteral("prev"));
  QSignalSpy spy(app_.get(), &AppController::notesStateChanged);

  app_->appendNoteEntry(QStringLiteral("   \n\t  \n  "));

  EXPECT_EQ(app_->notesState(), QStringLiteral("prev"));
  EXPECT_EQ(spy.count(), 0);
}

// ─── first-entry formatting ──────────────────────────────────────────

TEST_F(NotesAppendTest, FirstEntryEmitsHeadingThenBody) {
  ASSERT_TRUE(app_->notesState().isEmpty());
  QSignalSpy spy(app_.get(), &AppController::notesStateChanged);

  app_->appendNoteEntry(QStringLiteral("hello world"));

  const QStringList lines = app_->notesState().split(QLatin1Char('\n'));
  ASSERT_EQ(lines.size(), 3);
  EXPECT_TRUE(kStampLineRe.match(lines[0]).hasMatch()) << "first line should be '### YYYY-MM-DD HH:MM', got: " << lines[0].toStdString();
  EXPECT_EQ(lines[1], QString());
  EXPECT_EQ(lines[2], QStringLiteral("hello world"));
  EXPECT_EQ(spy.count(), 1);
}

TEST_F(NotesAppendTest, FirstEntryWhenStateIsWhitespaceOnly) {
  // Whitespace-only previous state must behave like empty — no separator
  // and no leading blank lines.
  app_->setNotesState(QStringLiteral("   \n\n  \n"));
  QSignalSpy spy(app_.get(), &AppController::notesStateChanged);

  app_->appendNoteEntry(QStringLiteral("body"));

  EXPECT_FALSE(app_->notesState().contains(QStringLiteral("----")));
  EXPECT_TRUE(app_->notesState().endsWith(QStringLiteral("\n\nbody")));
  EXPECT_EQ(spy.count(), 1);
}

// ─── subsequent entries ──────────────────────────────────────────────

TEST_F(NotesAppendTest, SecondEntryInsertsSeparatorAndHeading) {
  app_->setNotesState(QStringLiteral("first note"));
  QSignalSpy spy(app_.get(), &AppController::notesStateChanged);

  app_->appendNoteEntry(QStringLiteral("second note"));

  // Expected layout, one element per "\n"-delimited line:
  //
  //   first note
  //                       ← blank (HR needs preceding blank line)
  //   ----                ← HR (NotesHighlighter HR rule)
  //   ### YYYY-MM-DD HH:MM
  //                       ← blank (heading body separator)
  //   second note
  const QString out = app_->notesState();
  const QStringList lines = out.split(QLatin1Char('\n'));

  ASSERT_EQ(lines.size(), 6);
  EXPECT_EQ(lines[0], QStringLiteral("first note"));
  EXPECT_EQ(lines[1], QString());
  EXPECT_EQ(lines[2], QStringLiteral("----"));
  EXPECT_TRUE(kStampLineRe.match(lines[3]).hasMatch()) << "expected stamp heading on line 4, got: " << lines[3].toStdString();
  EXPECT_EQ(lines[4], QString());
  EXPECT_EQ(lines[5], QStringLiteral("second note"));
  EXPECT_EQ(spy.count(), 1);
}

TEST_F(NotesAppendTest, TrailingNewlinesAreCollapsedBeforeSeparator) {
  // Existing text with stray trailing newlines must not produce more
  // than two blank lines between the old body and the "----" separator.
  app_->setNotesState(QStringLiteral("old body\n\n\n\n"));

  app_->appendNoteEntry(QStringLiteral("new body"));

  // The contract is exactly two blank lines before the separator.
  EXPECT_TRUE(app_->notesState().contains(QStringLiteral("old body\n\n----\n")));
  EXPECT_FALSE(app_->notesState().contains(QStringLiteral("\n\n\n----")));
}

TEST_F(NotesAppendTest, BodyIsTrimmed) {
  app_->appendNoteEntry(QStringLiteral("\n\n  padded note  \n\n"));

  EXPECT_TRUE(app_->notesState().endsWith(QStringLiteral("padded note")));
  EXPECT_FALSE(app_->notesState().endsWith(QStringLiteral("\n")));
}

TEST_F(NotesAppendTest, MultilineBodyIsPreserved) {
  app_->appendNoteEntry(QStringLiteral("line one\nline two\nline three"));

  EXPECT_TRUE(app_->notesState().contains(QStringLiteral("line one\nline two\nline three")));
}

TEST_F(NotesAppendTest, ManyEntriesProduceOneSeparatorPerBoundary) {
  app_->appendNoteEntry(QStringLiteral("a"));
  app_->appendNoteEntry(QStringLiteral("b"));
  app_->appendNoteEntry(QStringLiteral("c"));

  const int separators = app_->notesState().count(QStringLiteral("\n----\n"));
  EXPECT_EQ(separators, 2) << "three entries should have exactly two '----' separators";
}

// ─── signal contract ─────────────────────────────────────────────────

TEST_F(NotesAppendTest, EmitsNotesStateChangedExactlyOncePerAppend) {
  QSignalSpy spy(app_.get(), &AppController::notesStateChanged);

  app_->appendNoteEntry(QStringLiteral("one"));
  app_->appendNoteEntry(QStringLiteral("two"));

  EXPECT_EQ(spy.count(), 2);
}

TEST_F(NotesAppendTest, NoSignalWhenInputRejected) {
  QSignalSpy spy(app_.get(), &AppController::notesStateChanged);

  app_->appendNoteEntry(QString());
  app_->appendNoteEntry(QStringLiteral("   "));
  app_->appendNoteEntry(QStringLiteral("\n\t\n"));

  EXPECT_EQ(spy.count(), 0);
}

// ─── Wiki-links / backlinks (HEAP-79) ─────────────────────────────────

TEST(NoteLinks, CollectsHeadingsDeduped) {
  const QString md = QStringLiteral("# Alpha\n\ntext\n## Beta\n### Alpha\n#### \n");
  const QStringList h = heap::notes::collectHeadings(md);
  ASSERT_EQ(h.size(), 2);  // "Alpha" deduped, empty heading skipped
  EXPECT_EQ(h.at(0), QString("Alpha"));
  EXPECT_EQ(h.at(1), QString("Beta"));
}

TEST(NoteLinks, BacklinksGroupByTargetWithResolution) {
  const QString md = QStringLiteral("# Alpha\n\nsee [[Beta]] here\n\n## Beta\n\nrefers to [[Alpha]] and [[Ghost]]\n");
  const QVariantList bl = heap::notes::collectBacklinks(md);
  // Targets: Alpha, Beta, Ghost (sorted, case-insensitive).
  ASSERT_EQ(bl.size(), 3);
  const QVariantMap alpha = bl.at(0).toMap();
  EXPECT_EQ(alpha.value("target").toString(), QString("Alpha"));
  EXPECT_TRUE(alpha.value("resolved").toBool());  // heading "# Alpha" exists
  ASSERT_EQ(alpha.value("refs").toList().size(), 1);
  EXPECT_EQ(alpha.value("refs").toList().at(0).toMap().value("line").toInt(), 7);

  const QVariantMap ghost = bl.at(2).toMap();
  EXPECT_EQ(ghost.value("target").toString(), QString("Ghost"));
  EXPECT_FALSE(ghost.value("resolved").toBool());  // no such heading
}

TEST(NoteLinks, HeadingOffsetFindsCaseInsensitive) {
  const QString md = QStringLiteral("# Alpha\n\n## Beta gamma\n");
  const int off = heap::notes::headingOffset(md, QStringLiteral("beta gamma"));
  EXPECT_EQ(md.mid(off, 12), QString("## Beta gamm"));
  EXPECT_EQ(heap::notes::headingOffset(md, QStringLiteral("nope")), -1);
}

// ─── headless boot (mirrors test_selection.cpp) ──────────────────────

// ─── Many notes instead of one blob (schema v8) ───────────────────────
//
// The delicate part is not the CRUD, it is the alias. `notesState` is what the
// editor binds to and what appendNoteEntry() writes, and it is now the body of
// whichever note is open. Anywhere those two drift apart, an edit survives
// until the next switch and then disappears.

class NotesTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->notes()->reset({});
    app_->setNotesState(QString());
  }

  void TearDown() override {
    app_.reset();
  }

  int count() const {
    return app_->notes()->rowCount();
  }

  QString titleOf(const QString& id) const {
    const int row = app_->notes()->indexOfId(id);
    return row >= 0 ? app_->notes()->items().at(row).title : QString();
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(NotesTest, ANewNoteIsCreatedAndOpened) {
  const QString id = app_->newNote(QStringLiteral("Standup"));

  EXPECT_EQ(count(), 1);
  EXPECT_EQ(app_->activeNoteId(), id);
  EXPECT_EQ(titleOf(id), QStringLiteral("Standup"));
}

// A note with no name cannot be found in a list.
TEST_F(NotesTest, ANewNoteWithNoTitleStillHasOne) {
  const QString id = app_->newNote();

  EXPECT_FALSE(titleOf(id).isEmpty());
}

// It opens saying what it is rather than as an empty page.
TEST_F(NotesTest, ANewNoteStartsWithItsHeading) {
  const QString id = app_->newNote(QStringLiteral("Standup"));

  EXPECT_TRUE(app_->noteBody(id).contains(QStringLiteral("# Standup")));
}

// ── The alias ──

TEST_F(NotesTest, NotesStateIsTheActiveNotesBody) {
  const QString id = app_->newNote(QStringLiteral("One"));

  app_->setNotesState(QStringLiteral("typed into the editor"));

  EXPECT_EQ(app_->noteBody(id), QStringLiteral("typed into the editor"));
}

// The failure this file exists for: type, switch away, switch back, and find
// what you typed still there.
TEST_F(NotesTest, TypingThenSwitchingKeepsWhatWasTyped) {
  const QString first = app_->newNote(QStringLiteral("One"));
  const QString second = app_->newNote(QStringLiteral("Two"));

  app_->setActiveNoteId(first);
  app_->setNotesState(QStringLiteral("first body"));
  app_->setActiveNoteId(second);
  app_->setNotesState(QStringLiteral("second body"));
  app_->setActiveNoteId(first);

  EXPECT_EQ(app_->notesState(), QStringLiteral("first body"));
  EXPECT_EQ(app_->noteBody(second), QStringLiteral("second body"));
}

TEST_F(NotesTest, SwitchingNotesReplacesWhatTheEditorShows) {
  const QString first = app_->newNote(QStringLiteral("One"));
  app_->setNotesState(QStringLiteral("first"));
  const QString second = app_->newNote(QStringLiteral("Two"));
  app_->setNotesState(QStringLiteral("second"));

  app_->setActiveNoteId(first);

  EXPECT_EQ(app_->notesState(), QStringLiteral("first"));
}

TEST_F(NotesTest, SwitchingNotesTellsTheEditorToReload) {
  const QString first = app_->newNote(QStringLiteral("One"));
  const QString second = app_->newNote(QStringLiteral("Two"));
  QSignalSpy spy(app_.get(), &AppController::notesStateChanged);

  app_->setActiveNoteId(first);

  EXPECT_GE(spy.count(), 1);
  EXPECT_NE(app_->activeNoteId(), second);
}

// Writing a body straight to a note the user is not looking at must not
// silently change what the editor shows.
TEST_F(NotesTest, WritingToAnInactiveNoteLeavesTheEditorAlone) {
  const QString first = app_->newNote(QStringLiteral("One"));
  const QString second = app_->newNote(QStringLiteral("Two"));
  app_->setNotesState(QStringLiteral("second body"));

  app_->setNoteBody(first, QStringLiteral("written behind the scenes"));

  EXPECT_EQ(app_->notesState(), QStringLiteral("second body"));
  EXPECT_EQ(app_->noteBody(first), QStringLiteral("written behind the scenes"));
}

// QuickCapture appends to notesState; it has to land in a real note.
TEST_F(NotesTest, AppendingAnEntryReachesTheActiveNote) {
  const QString id = app_->newNote(QStringLiteral("Inbox"));
  app_->setNotesState(QString());

  app_->appendNoteEntry(QStringLiteral("something captured"));

  EXPECT_TRUE(app_->noteBody(id).contains(QStringLiteral("something captured")));
}

// ── Deleting ──

TEST_F(NotesTest, DeletingANoteRemovesIt) {
  const QString id = app_->newNote(QStringLiteral("One"));

  app_->deleteNote(id);

  EXPECT_EQ(count(), 0);
}

// An empty editor after a delete reads as the rest of the notes having gone
// too, so the selection lands on a neighbour.
TEST_F(NotesTest, DeletingTheOpenNoteOpensANeighbour) {
  const QString first = app_->newNote(QStringLiteral("One"));
  const QString second = app_->newNote(QStringLiteral("Two"));
  app_->setActiveNoteId(second);

  app_->deleteNote(second);

  EXPECT_EQ(app_->activeNoteId(), first);
  EXPECT_EQ(app_->notesState(), app_->noteBody(first));
}

TEST_F(NotesTest, DeletingTheLastNoteLeavesNothingOpen) {
  const QString id = app_->newNote(QStringLiteral("Only"));

  app_->deleteNote(id);

  EXPECT_TRUE(app_->activeNoteId().isEmpty());
  EXPECT_TRUE(app_->notesState().isEmpty());
}

TEST_F(NotesTest, DeletingANoteThatIsNotOpenLeavesTheEditorAlone) {
  const QString first = app_->newNote(QStringLiteral("One"));
  const QString second = app_->newNote(QStringLiteral("Two"));
  app_->setNotesState(QStringLiteral("second body"));

  app_->deleteNote(first);

  EXPECT_EQ(app_->activeNoteId(), second);
  EXPECT_EQ(app_->notesState(), QStringLiteral("second body"));
}

TEST_F(NotesTest, DeletingSomethingThatIsNotThereDoesNothing) {
  app_->newNote(QStringLiteral("One"));

  app_->deleteNote(QStringLiteral("nobody"));

  EXPECT_EQ(count(), 1);
}

// ── Renaming, pinning, filing ──

TEST_F(NotesTest, RenamingChangesTheTitle) {
  const QString id = app_->newNote(QStringLiteral("Old"));

  app_->renameNote(id, QStringLiteral("New"));

  EXPECT_EQ(titleOf(id), QStringLiteral("New"));
}

// A blank name would make the note unfindable, so it is refused rather than
// applied.
TEST_F(NotesTest, RenamingToNothingIsRefused) {
  const QString id = app_->newNote(QStringLiteral("Keep"));

  app_->renameNote(id, QStringLiteral("   "));

  EXPECT_EQ(titleOf(id), QStringLiteral("Keep"));
}

TEST_F(NotesTest, PinningIsRemembered) {
  const QString id = app_->newNote(QStringLiteral("One"));

  app_->setNotePinned(id, true);

  const int row = app_->notes()->indexOfId(id);
  EXPECT_TRUE(app_->notes()->items().at(row).pinned);
}

TEST_F(NotesTest, AFolderIsRemembered) {
  const QString id = app_->newNote(QStringLiteral("One"));

  app_->moveNoteToFolder(id, QStringLiteral("meetings/2026"));

  const int row = app_->notes()->indexOfId(id);
  EXPECT_EQ(app_->notes()->items().at(row).folder, QStringLiteral("meetings/2026"));
}

// "/meetings/" and "meetings" are one folder, not two — they have to be, or
// the tree grows a duplicate branch nobody typed.
TEST_F(NotesTest, AFolderPathIsNormalised) {
  const QString id = app_->newNote(QStringLiteral("One"));

  app_->moveNoteToFolder(id, QStringLiteral("/meetings/"));

  const int row = app_->notes()->indexOfId(id);
  EXPECT_EQ(app_->notes()->items().at(row).folder, QStringLiteral("meetings"));
}

TEST_F(NotesTest, FoldersAreListedOnceAndSorted) {
  app_->moveNoteToFolder(app_->newNote(QStringLiteral("a")), QStringLiteral("zeta"));
  app_->moveNoteToFolder(app_->newNote(QStringLiteral("b")), QStringLiteral("alpha"));
  app_->moveNoteToFolder(app_->newNote(QStringLiteral("c")), QStringLiteral("alpha"));

  EXPECT_EQ(app_->noteFolders(), (QStringList{QStringLiteral("alpha"), QStringLiteral("zeta")}));
}

TEST_F(NotesTest, ANoteWithNoFolderIsNotAFolder) {
  app_->newNote(QStringLiteral("loose"));

  EXPECT_TRUE(app_->noteFolders().isEmpty());
}

// ── The model ──

// The list carries no bodies: fifty notes would be fifty documents crossing the
// QML boundary on every repaint.
TEST_F(NotesTest, TheModelDoesNotCarryBodies) {
  app_->newNote(QStringLiteral("One"));

  EXPECT_LT(app_->notes()->roleOf(QStringLiteral("body")), 0);
  EXPECT_GE(app_->notes()->roleOf(QStringLiteral("title")), 0);
}

// It does carry a preview, so a row can say what the note is about.
TEST_F(NotesTest, TheModelCarriesAnExcerpt) {
  const QString id = app_->newNote(QStringLiteral("Standup"));
  app_->setNoteBody(id, QStringLiteral("# Standup\n\nthe first real line\n"));

  const int role = app_->notes()->roleOf(QStringLiteral("excerpt"));
  ASSERT_GE(role, 0);
  const int row = app_->notes()->indexOfId(id);
  EXPECT_EQ(app_->notes()->data(app_->notes()->index(row, 0), role).toString(), QStringLiteral("the first real line"));
}

// Repeating the heading back tells the reader nothing they cannot already see.
TEST_F(NotesTest, TheExcerptSkipsTheHeading) {
  const QString id = app_->newNote(QStringLiteral("Title"));
  app_->setNoteBody(id, QStringLiteral("# Title\n\n## Sub\n\nbody text"));

  const int role = app_->notes()->roleOf(QStringLiteral("excerpt"));
  const int row = app_->notes()->indexOfId(id);
  const QString excerpt = app_->notes()->data(app_->notes()->index(row, 0), role).toString();

  EXPECT_NE(excerpt, QStringLiteral("Title"));
  EXPECT_FALSE(excerpt.startsWith(QLatin1Char('#')));
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");

  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  QApplication qapp(argc, argv);

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
