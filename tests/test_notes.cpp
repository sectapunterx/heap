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
