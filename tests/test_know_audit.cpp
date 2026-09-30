// Regressions from the 2026-09-30 audit, notes / docs / markdown area.
//
// Each block names the audit item it pins. The pure halves (vault planning,
// markdown ops) are covered next to their code; these go through a real
// AppController and, for the vault, through the disk.

#include "AppController.h"
#include "CodeHighlighter.h"
#include "Models.h"

#include <QApplication>
#include <QClipboard>
#include <QGuiApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTextBlock>
#include <QTextDocument>
#include <QTextLayout>
#include <QUrl>

#include <gtest/gtest.h>

namespace {

class KnowAuditTest : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->notes()->reset({});
    app_->setNotesState(QString());
    // The test profile persists between runs; start from no pages either.
    app_->docPages()->reset({});
    ASSERT_TRUE(dir_.isValid());
  }

  void TearDown() override {
    app_.reset();
  }

  QString path(const QString& rel) const {
    return dir_.path() + QLatin1Char('/') + rel;
  }

  void writeFile(const QString& rel, const QByteArray& bytes) const {
    QDir().mkpath(QFileInfo(path(rel)).absolutePath());
    QFile f(path(rel));
    ASSERT_TRUE(f.open(QIODevice::WriteOnly));
    f.write(bytes);
  }

  QString readFile(const QString& full) const {
    QFile f(full);
    if(!f.open(QIODevice::ReadOnly)) {
      return {};
    }
    return QString::fromUtf8(f.readAll());
  }

  const Note* byTitle(const QString& title) const {
    for(const Note& n : app_->notes()->items()) {
      if(n.title == title) {
        return &n;
      }
    }
    return nullptr;
  }

  QUrl url(const QString& rel = QString()) const {
    return QUrl::fromLocalFile(rel.isEmpty() ? dir_.path() : path(rel));
  }

  QTemporaryDir dir_;
  std::unique_ptr<AppController> app_;
};

}  // namespace

// ── KNOW-1: a re-import never silently overwrites an edit made in heap ──

TEST_F(KnowAuditTest, Know1_ReimportKeepsANoteEditedInHeap) {
  writeFile(QStringLiteral("vault/Standup.md"), "from disk");
  app_->importNotesFolder(url(QStringLiteral("vault")));
  ASSERT_EQ(app_->notes()->rowCount(), 1);
  const QString id = app_->notes()->items().at(0).id;

  app_->setNoteBody(id, QStringLiteral("edited in heap"));
  const QVariantMap r = app_->importNotesFolder(url(QStringLiteral("vault")));

  EXPECT_EQ(r.value("kept").toInt(), 1);
  EXPECT_EQ(app_->noteBody(id), QStringLiteral("edited in heap"));
  EXPECT_EQ(app_->notes()->rowCount(), 1);
}

TEST_F(KnowAuditTest, Know1_EditedOnBothSidesKeepsBothVersions) {
  writeFile(QStringLiteral("vault/Standup.md"), "v1");
  app_->importNotesFolder(url(QStringLiteral("vault")));
  const QString id = app_->notes()->items().at(0).id;

  app_->setNoteBody(id, QStringLiteral("heap side"));
  writeFile(QStringLiteral("vault/Standup.md"), "disk side");
  const QVariantMap r = app_->importNotesFolder(url(QStringLiteral("vault")));

  EXPECT_EQ(r.value("conflicts").toInt(), 1);
  ASSERT_EQ(app_->notes()->rowCount(), 2);
  EXPECT_EQ(app_->noteBody(id), QStringLiteral("heap side"));
  bool sawDisk = false;
  for(const Note& n : app_->notes()->items()) {
    sawDisk = sawDisk || n.body == QStringLiteral("disk side");
  }
  EXPECT_TRUE(sawDisk);
}

// The editor debounces: what is typed but not yet written must count as heap's.
TEST_F(KnowAuditTest, Know1_UnflushedTypingCountsAsAnEdit) {
  writeFile(QStringLiteral("vault/Standup.md"), "v1");
  app_->importNotesFolder(url(QStringLiteral("vault")));
  const QString id = app_->notes()->items().at(0).id;
  app_->setActiveNoteId(id);

  // What NotesView does on aboutToChangeActiveNote: flush the text field.
  QObject::connect(app_.get(), &AppController::aboutToChangeActiveNote, app_.get(), [this]() {
    app_->setNotesState(QStringLiteral("typed a moment ago"));
  });
  writeFile(QStringLiteral("vault/Standup.md"), "v2 on disk");
  app_->importNotesFolder(url(QStringLiteral("vault")));

  EXPECT_EQ(app_->noteBody(id), QStringLiteral("typed a moment ago"));
}

TEST_F(KnowAuditTest, Know1_TheWholeImportIsOneUndoStep) {
  writeFile(QStringLiteral("vault/A.md"), "a");
  writeFile(QStringLiteral("vault/B.md"), "b");
  writeFile(QStringLiteral("vault/sub/C.md"), "c");
  const int before = app_->undoDepth();

  app_->importNotesFolder(url(QStringLiteral("vault")));
  ASSERT_EQ(app_->notes()->rowCount(), 3);
  EXPECT_EQ(app_->undoDepth(), before + 1);
  EXPECT_TRUE(app_->hasPendingUndo());

  app_->undo();
  EXPECT_EQ(app_->notes()->rowCount(), 0);
}

TEST_F(KnowAuditTest, Know1_PreviewChangesNothing) {
  writeFile(QStringLiteral("vault/A.md"), "a");
  const QVariantMap r = app_->previewNotesFolder(url(QStringLiteral("vault")));
  EXPECT_EQ(r.value("imported").toInt(), 1);
  EXPECT_EQ(r.value("files").toInt(), 1);
  EXPECT_EQ(app_->notes()->rowCount(), 0);
}

// ── KNOW-2: heap's own export comes back whole ──

TEST_F(KnowAuditTest, Know2_DuplicateTitlesSurviveExportAndReimport) {
  const QString a = app_->newNote(QStringLiteral("Meeting"));
  const QString b = app_->newNote(QStringLiteral("Meeting"));
  const QString c = app_->newNote(QStringLiteral("meeting"));
  app_->setNoteBody(a, QStringLiteral("alpha"));
  app_->setNoteBody(b, QStringLiteral("bravo"));
  app_->setNoteBody(c, QStringLiteral("charlie"));

  const QString out = app_->exportNotesFolder(url(), QStringLiteral("export")).value("folder").toString();
  // Into an empty profile: every file becomes its own note again.
  app_->notes()->reset({});
  app_->setNotesState(QString());
  app_->importNotesFolder(QUrl::fromLocalFile(out));
  ASSERT_EQ(app_->notes()->rowCount(), 3);
  EXPECT_EQ(app_->noteBody(a), QStringLiteral("alpha"));
  EXPECT_EQ(app_->noteBody(b), QStringLiteral("bravo"));
  EXPECT_EQ(app_->noteBody(c), QStringLiteral("charlie"));

  // And into the same profile: nothing doubles, nothing is merged.
  const QVariantMap again = app_->importNotesFolder(QUrl::fromLocalFile(out));
  EXPECT_EQ(app_->notes()->rowCount(), 3);
  EXPECT_EQ(again.value("unchanged").toInt(), 3);
}

// ── KNOW-3: export never overwrites ──

TEST_F(KnowAuditTest, Know3_ExportNeverOverwritesAnExistingFile) {
  writeFile(QStringLiteral("team/Meeting.md"), "the team's own notes");
  app_->newNote(QStringLiteral("Meeting"));

  const QVariantMap r = app_->exportNotesFolder(url(QStringLiteral("team")));

  EXPECT_EQ(readFile(path(QStringLiteral("team/Meeting.md"))), QStringLiteral("the team's own notes"));
  EXPECT_EQ(r.value("written").toInt(), 1);
  const QString folder = r.value("folder").toString();
  EXPECT_TRUE(QFile::exists(QDir(folder).filePath(QStringLiteral("Meeting.md"))));
}

TEST_F(KnowAuditTest, Know3_ATakenExportNameGetsASuffix) {
  writeFile(QStringLiteral("out/keep.md"), "keep");
  app_->newNote(QStringLiteral("One"));

  const QString folder = app_->exportNotesFolder(url(), QStringLiteral("out")).value("folder").toString();

  EXPECT_NE(QDir::fromNativeSeparators(folder), path(QStringLiteral("out")));
  EXPECT_EQ(readFile(path(QStringLiteral("out/keep.md"))), QStringLiteral("keep"));
}

// ── KNOW-9 / KNOW-10: what an import refuses ──

TEST_F(KnowAuditTest, Know9_ImportDoesNotFollowAJunctionOutOfTheVault) {
#ifdef Q_OS_WIN
  writeFile(QStringLiteral("vault/Real.md"), "real");
  writeFile(QStringLiteral("elsewhere/Outside.md"), "outside");
  const int rc = QProcess::execute(QStringLiteral("cmd"),
                                   {QStringLiteral("/c"),
                                    QStringLiteral("mklink"),
                                    QStringLiteral("/J"),
                                    QDir::toNativeSeparators(path(QStringLiteral("vault/link"))),
                                    QDir::toNativeSeparators(path(QStringLiteral("elsewhere")))});
  if(rc != 0) {
    GTEST_SKIP() << "could not create a junction";
  }
  // And one pointing back at the vault itself, the loop the audit hit.
  QProcess::execute(QStringLiteral("cmd"),
                    {QStringLiteral("/c"),
                     QStringLiteral("mklink"),
                     QStringLiteral("/J"),
                     QDir::toNativeSeparators(path(QStringLiteral("vault/loop"))),
                     QDir::toNativeSeparators(path(QStringLiteral("vault")))});

  app_->importNotesFolder(url(QStringLiteral("vault")));

  ASSERT_EQ(app_->notes()->rowCount(), 1);
  EXPECT_EQ(app_->notes()->items().at(0).title, QStringLiteral("Real"));
#else
  GTEST_SKIP() << "junctions are Windows-only";
#endif
}

TEST_F(KnowAuditTest, Know10_BinaryAndHugeFilesAreSkippedWithAWarning) {
  writeFile(QStringLiteral("vault/Real.md"), "real");
  writeFile(QStringLiteral("vault/blob.md"), QByteArray("PK\x03\x04\0\0\0", 7));
  writeFile(QStringLiteral("vault/huge.md"), QByteArray(5 * 1024 * 1024, 'x'));

  const QVariantMap r = app_->importNotesFolder(url(QStringLiteral("vault")));

  EXPECT_EQ(app_->notes()->rowCount(), 1);
  EXPECT_EQ(r.value("skipped").toInt(), 2);
  EXPECT_EQ(r.value("warnings").toStringList().size(), 2);
}

TEST_F(KnowAuditTest, Know10_ObsidianTagsSurviveARoundTrip) {
  writeFile(QStringLiteral("vault/Plan.md"), "---\ntags: [work, q3]\naliases:\n  - Plan B\n---\nbody");
  app_->importNotesFolder(url(QStringLiteral("vault")));
  const QString out = app_->exportNotesFolder(url(), QStringLiteral("back")).value("folder").toString();
  const QString text = readFile(QDir(out).filePath(QStringLiteral("Plan.md")));
  EXPECT_TRUE(text.contains(QStringLiteral("tags: [work, q3]")));
  EXPECT_TRUE(text.contains(QStringLiteral("  - Plan B")));
}

// ── PLAT-21: a profile export carries what was just typed ──

TEST_F(KnowAuditTest, Plat21_ProfileExportIncludesTheLatestNoteAndPageEdits) {
  const QString id = app_->newNote(QStringLiteral("Fresh"));
  app_->setNoteBody(id, QStringLiteral("written a moment ago"));
  const QString page = app_->newDocPage(QStringLiteral("Runbook"));
  app_->setDocPageBody(page, QStringLiteral("page body"));

  // The editors flush on request; model one that still has keystrokes.
  QObject::connect(app_.get(), &AppController::flushEditorsRequested, app_.get(), [this]() {
    app_->setNotesState(QStringLiteral("typed, not yet saved"));
  });

  const QJsonObject root = QJsonDocument::fromJson(app_->exportActiveProfileJson().toUtf8()).object();
  const QJsonObject prof = root.value("profile").toObject();
  bool sawNote = false;
  for(const auto& v : prof.value("notes").toArray()) {
    sawNote = sawNote || v.toObject().value("body").toString() == QStringLiteral("typed, not yet saved");
  }
  bool sawPage = false;
  for(const auto& v : prof.value("docPages").toArray()) {
    sawPage = sawPage || v.toObject().value("body").toString() == QStringLiteral("page body");
  }
  EXPECT_TRUE(sawNote);
  EXPECT_TRUE(sawPage);
}

// ── KNOW-11 / C: rename keeps links, H1 and undo ──

TEST_F(KnowAuditTest, Know11_RenameRewritesLinksAndHeadingAndIsUndoable) {
  const QString target = app_->newNote(QStringLiteral("Plan"));
  const QString other = app_->newNote(QStringLiteral("Diary"));
  app_->setNoteBody(other, QStringLiteral("see [[Plan]] and [[plan#Risks]]"));

  app_->renameNote(target, QStringLiteral("Roadmap"));

  EXPECT_EQ(app_->noteBody(other), QStringLiteral("see [[Roadmap]] and [[Roadmap#Risks]]"));
  EXPECT_TRUE(app_->noteBody(target).startsWith(QStringLiteral("# Roadmap")));
  app_->undo();
  EXPECT_EQ(app_->noteBody(other), QStringLiteral("see [[Plan]] and [[plan#Risks]]"));
  const int row = app_->notes()->indexOfId(target);
  EXPECT_EQ(app_->notes()->items().at(row).title, QStringLiteral("Plan"));
}

TEST_F(KnowAuditTest, KnowC_TitleFollowsTheH1WhileTheyAgree) {
  const QString id = app_->newNote();
  app_->setNotesState(QStringLiteral("# Release checklist\n\nbody"));
  const int row = app_->notes()->indexOfId(id);
  EXPECT_EQ(app_->notes()->items().at(row).title, QStringLiteral("Release checklist"));
}

TEST_F(KnowAuditTest, KnowC_PinAndMoveAreUndoable) {
  const QString id = app_->newNote(QStringLiteral("N"));
  app_->setNotePinned(id, true);
  app_->moveNoteToFolder(id, QStringLiteral("work"));
  app_->undo();
  EXPECT_TRUE(app_->notes()->items().at(app_->notes()->indexOfId(id)).folder.isEmpty());
  app_->undo();
  EXPECT_FALSE(app_->notes()->items().at(app_->notes()->indexOfId(id)).pinned);
}

TEST_F(KnowAuditTest, KnowC_FoldersCanBeRenamedAndRemovedKeepingNotes) {
  const QString a = app_->newNote(QStringLiteral("A"), QStringLiteral("meetings"));
  const QString b = app_->newNote(QStringLiteral("B"), QStringLiteral("meetings/2026"));
  EXPECT_EQ(app_->renameNoteFolder(QStringLiteral("meetings"), QStringLiteral("team")), 2);
  EXPECT_EQ(app_->noteFolders(), (QStringList{QStringLiteral("team"), QStringLiteral("team/2026")}));
  EXPECT_EQ(app_->removeNoteFolder(QStringLiteral("team/2026")), 1);
  EXPECT_EQ(app_->notes()->items().at(app_->notes()->indexOfId(b)).folder, QStringLiteral("team"));
  EXPECT_EQ(app_->notes()->rowCount(), 2);
  EXPECT_EQ(app_->notes()->items().at(app_->notes()->indexOfId(a)).folder, QStringLiteral("team"));
}

// ── KNOW-6 / TASKS-16: search reaches every note and every doc page ──

TEST_F(KnowAuditTest, Know6_PaletteFindsWordsInNotesThatAreNotOpenAndInDocPages) {
  const QString hidden = app_->newNote(QStringLiteral("Hidden"));
  app_->setNoteBody(hidden, QStringLiteral("# Hidden\n\n## Deploy\n\nthe zebracorn rollout"));
  app_->newNote(QStringLiteral("Open one"));  // now the open note
  const QString page = app_->newDocPage(QStringLiteral("Runbook"));
  app_->setDocPageBody(page, QStringLiteral("# Runbook\n\nrestart the quokkafleet"));

  const QVariantList notes = app_->searchFullText(QStringLiteral("zebracorn"));
  ASSERT_EQ(notes.size(), 1);
  EXPECT_EQ(notes.at(0).toMap().value("kind").toString(), QStringLiteral("note"));
  EXPECT_EQ(notes.at(0).toMap().value("noteId").toString(), hidden);
  EXPECT_EQ(notes.at(0).toMap().value("label").toString(), QStringLiteral("Hidden › Deploy"));

  const QVariantList pages = app_->searchFullText(QStringLiteral("quokkafleet"));
  ASSERT_EQ(pages.size(), 1);
  EXPECT_EQ(pages.at(0).toMap().value("kind").toString(), QStringLiteral("docPage"));
  EXPECT_EQ(pages.at(0).toMap().value("pageId").toString(), page);

  // And the palette's own list carries both, in the row shape it knows.
  bool sawNote = false;
  bool sawPage = false;
  for(const QVariant& v : app_->commandPaletteEntries()) {
    const QVariantMap m = v.toMap();
    sawNote = sawNote || (m.value("noteId").toString() == hidden && m.value("body").toString().contains(QStringLiteral("zebracorn")));
    sawPage = sawPage || (m.value("pageId").toString() == page && m.value("body").toString().contains(QStringLiteral("quokkafleet")));
  }
  EXPECT_TRUE(sawNote);
  EXPECT_TRUE(sawPage);
}

TEST_F(KnowAuditTest, Know19_TheNoteFilterMatchesTheWholeBody) {
  const QString a = app_->newNote(QStringLiteral("A"));
  app_->setNoteBody(a, QStringLiteral("# A\n\nline one\n\n") + QString(500, QLatin1Char('x')) + QStringLiteral("\n\nneedle deep inside"));
  app_->newNote(QStringLiteral("B"));
  EXPECT_EQ(app_->notesMatching(QStringLiteral("deep needle")), QStringList{a});
}

TEST_F(KnowAuditTest, Know12_MentionsResolveToPeopleInAnyScript) {
  app_->people()->reset({});
  Person p;
  p.id = QStringLiteral("p-oleg");
  p.name = QStringLiteral("Олег Т.");
  app_->people()->upsert(p);
  EXPECT_EQ(app_->personIdForHandle(QStringLiteral("@Олег_Т.")), QStringLiteral("p-oleg"));
  EXPECT_EQ(app_->personIdForHandle(QStringLiteral("олег")), QStringLiteral("p-oleg"));
}

// ── KNOW-20: copy as Markdown takes every note and every doc page ──

TEST_F(KnowAuditTest, Know20_CopyAsMarkdownHasAllNotesAndPages) {
  const QString a = app_->newNote(QStringLiteral("Alpha"));
  app_->setNoteBody(a, QStringLiteral("# Alpha\n\nalpha body"));
  const QString b = app_->newNote(QStringLiteral("Bravo"));
  app_->setNoteBody(b, QStringLiteral("bravo body"));
  const QString parent = app_->newDocPage(QStringLiteral("Runbook"));
  app_->setDocPageBody(parent, QStringLiteral("page body"));
  app_->newDocPage(QStringLiteral("Child"), parent);

  app_->copyActiveProfileMarkdownToClipboard();
  const QString md = QGuiApplication::clipboard()->text();

  EXPECT_TRUE(md.contains(QStringLiteral("### Alpha\n\nalpha body"))) << md.toStdString();
  EXPECT_TRUE(md.contains(QStringLiteral("bravo body")));
  EXPECT_TRUE(md.contains(QStringLiteral("## Docs")));
  EXPECT_TRUE(md.contains(QStringLiteral("### Runbook")));
  EXPECT_TRUE(md.contains(QStringLiteral("### › Child")));
}

// ── C: code highlighting in the preview ──

namespace {

// The format the highlighter left at `pos` in the first block.
QTextCharFormat formatAt(QTextDocument& doc, int pos) {
  const QTextBlock block = doc.firstBlock();
  for(const QTextLayout::FormatRange& r : block.layout()->formats()) {
    if(pos >= r.start && pos < r.start + r.length) {
      return r.format;
    }
  }
  return {};
}

}  // namespace

TEST(KnowCodeHighlight, AHashInsideABashStringIsNotAComment) {
  QTextDocument doc;
  CodeHighlighter h;
  h.setLanguage(QStringLiteral("Bash"));  // any case
  h.setDocument(&doc);
  doc.setPlainText(QStringLiteral("echo \"#1 not a comment\" # a comment"));
  h.rehighlight();
  EXPECT_FALSE(formatAt(doc, 7).fontItalic()) << "inside the string";
  EXPECT_TRUE(formatAt(doc, 27).fontItalic()) << "the real comment";
}

TEST(KnowCodeHighlight, LanguageNamesAreCaseInsensitiveWithAliases) {
  EXPECT_EQ(CodeHighlighter::canonicalLanguage(QStringLiteral("C++")), QStringLiteral("cpp"));
  EXPECT_EQ(CodeHighlighter::canonicalLanguage(QStringLiteral("YML")), QStringLiteral("yaml"));
  EXPECT_EQ(CodeHighlighter::canonicalLanguage(QStringLiteral("Golang")), QStringLiteral("go"));
  EXPECT_EQ(CodeHighlighter::canonicalLanguage(QStringLiteral("zsh")), QStringLiteral("sh"));
  // And the languages beyond the original five get colour at all.
  for(const char* lang : {"go", "rust", "java", "sql", "json", "css", "xml", "powershell", "lua"}) {
    QTextDocument doc;
    CodeHighlighter h;
    h.setLanguage(QString::fromLatin1(lang));
    h.setDocument(&doc);
    doc.setPlainText(QStringLiteral("select \"s\" + 1 // x -- y # z <a b=\"c\"> +add"));
    h.rehighlight();
    EXPECT_FALSE(doc.firstBlock().layout()->formats().isEmpty()) << lang;
  }
}

int main(int argc, char** argv) {
  QStandardPaths::setTestModeEnabled(true);
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QApplication app(argc, argv);
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
