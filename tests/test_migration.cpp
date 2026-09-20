// Schema migration on load (HEAP-146).
//
// A v3 profile carries `deadline` as a bare date. Opening it must upgrade the
// file to v4 in place, retain a pre-migration copy, and never re-migrate on the
// next launch. Runs headless against QStandardPaths test mode, so it never
// touches the user's real AppDataLocation.

#include "AppController.h"
#include "StateSerializer.h"

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace {

QString appDataDir() {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QString statePath() {
  return appDataDir() + "/state.json";
}

QString backupDir() {
  return appDataDir() + "/backups";
}

void writeFile(const QString& path, const QByteArray& bytes) {
  QDir().mkpath(QFileInfo(path).absolutePath());
  QFile f(path);
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write(bytes);
}

QJsonObject readJson(const QString& path) {
  QFile f(path);
  if(!f.open(QIODevice::ReadOnly)) {
    return {};
  }
  return QJsonDocument::fromJson(f.readAll()).object();
}

// A schema-v3 document with one dated task, one undated task, and one task whose
// deadline is the empty string the app used to write for "no deadline".
QByteArray v3Document() {
  return R"({
  "schemaVersion": 3,
  "activeProfileId": "default",
  "events": [],
  "profiles": [
    {
      "id": "default",
      "name": "Example",
      "color": "#5cc2dd",
      "createdAt": "2026-01-01T00:00:00",
      "people": [],
      "statuses": [{"id": "todo", "name": "To Do", "color": "#888888"}],
      "tasks": [
        {"id": "T-1", "title": "dated", "priority": "P1", "status": "todo",
         "deadline": "2026-07-08", "statusChangedAt": "2026-07-01T09:00:00", "archived": false},
        {"id": "T-2", "title": "undated", "priority": "P2", "status": "todo",
         "deadline": "", "statusChangedAt": "2026-07-01T09:00:00", "archived": false},
        {"id": "T-3", "title": "timed ticket", "priority": "P0", "status": "prog",
         "deadline": "2026-07-09", "trackedSeconds": 90, "recurrence": "every:day",
         "externalId": "68", "externalUrl": "https://x.invalid/68", "externalProvider": "github",
         "statusChangedAt": "2026-07-01T09:00:00", "archived": false}
      ]
    }
  ]
})";
}

void clearAppData() {
  QDir(appDataDir()).removeRecursively();
  QDir().mkpath(appDataDir());
}

const Task* taskById(AppController& app, const QString& id) {
  for(const Task& t : app.tasks()->items()) {
    if(t.id == id) {
      return &t;
    }
  }
  return nullptr;
}

class MigrationTest : public ::testing::Test {
 protected:
  void SetUp() override {
    clearAppData();
  }
};

}  // namespace

TEST_F(MigrationTest, V3DeadlineBecomesMidnightScheduledAndDue) {
  writeFile(statePath(), v3Document());

  AppController app;
  const Task* dated = taskById(app, QStringLiteral("T-1"));
  ASSERT_NE(dated, nullptr);
  EXPECT_EQ(dated->scheduledAt, QDateTime(QDate(2026, 7, 8), QTime(0, 0)));
  EXPECT_EQ(dated->dueAt, QDateTime(QDate(2026, 7, 8), QTime(0, 0)));
  EXPECT_FALSE(dated->hasTime);

  const Task* undated = taskById(app, QStringLiteral("T-2"));
  ASSERT_NE(undated, nullptr);
  EXPECT_FALSE(undated->scheduledAt.isValid());
  EXPECT_FALSE(undated->dueAt.isValid());
}

TEST_F(MigrationTest, MigrationPreservesEveryOtherField) {
  writeFile(statePath(), v3Document());

  AppController app;
  const Task* t = taskById(app, QStringLiteral("T-3"));
  ASSERT_NE(t, nullptr);
  EXPECT_EQ(t->trackedSeconds, 90);
  EXPECT_EQ(t->recurrence, QString("every:day"));
  EXPECT_EQ(t->externalId, QString("68"));
  EXPECT_EQ(t->externalProvider, QString("github"));
  EXPECT_EQ(t->status, QString("prog"));
}

TEST_F(MigrationTest, OpeningAV3ProfileRetainsAPreMigrationBackup) {
  const QByteArray original = v3Document();
  writeFile(statePath(), original);

  AppController app;
  const QStringList kept = QDir(backupDir()).entryList({"state-premigration-*.json"}, QDir::Files);
  ASSERT_EQ(kept.size(), 1) << "expected exactly one retained pre-migration copy";

  QFile f(backupDir() + "/" + kept.first());
  ASSERT_TRUE(f.open(QIODevice::ReadOnly));
  EXPECT_EQ(f.readAll(), original) << "the retained copy must be the untouched original";
}

TEST_F(MigrationTest, SaveUpgradesTheFileToV4) {
  writeFile(statePath(), v3Document());

  AppController app;
  app.flushSave();

  const QJsonObject root = readJson(statePath());
  EXPECT_EQ(root.value("schemaVersion").toInt(), heap::state::kSchemaVersion);

  const QJsonObject task = root.value("profiles").toArray().at(0).toObject().value("tasks").toArray().at(0).toObject();
  EXPECT_FALSE(task.contains("deadline")) << "the legacy key must be gone";
  EXPECT_EQ(task.value("scheduledAt").toString().left(10), QString("2026-07-08"));
}

TEST_F(MigrationTest, ReopeningAV4ProfileDoesNotReMigrate) {
  writeFile(statePath(), v3Document());
  {
    AppController first;
    first.flushSave();
  }
  const int afterFirst = QDir(backupDir()).entryList({"state-premigration-*.json"}, QDir::Files).size();
  ASSERT_EQ(afterFirst, 1);

  const QByteArray migrated = [] {
    QFile f(statePath());
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
  }();

  {
    AppController second;  // the version gate must hold
    second.flushSave();
  }

  EXPECT_EQ(QDir(backupDir()).entryList({"state-premigration-*.json"}, QDir::Files).size(), 1)
      << "a second launch must not retain another pre-migration copy";

  QFile f(statePath());
  ASSERT_TRUE(f.open(QIODevice::ReadOnly));
  EXPECT_EQ(f.readAll(), migrated) << "re-saving a v4 profile must be a no-op on its content";
}

// migrateState is the ladder step itself: idempotent, and safe to call twice.
TEST_F(MigrationTest, MigrateStateIsIdempotent) {
  QJsonObject root = QJsonDocument::fromJson(v3Document()).object();

  EXPECT_TRUE(heap::state::migrateState(root, 3));
  const QJsonObject once = root;
  EXPECT_FALSE(heap::state::migrateState(root, heap::state::kSchemaVersion));
  EXPECT_EQ(root, once);
}

// The ladder is rung-gated, not "run everything below the current version".
// A document entering at v4 must walk past the v3→v4 rung: that rung consumes
// `deadline`, and a task that legitimately carries scheduledAt/dueAt plus a
// `deadline` key from a future shape must come out untouched.
TEST_F(MigrationTest, LadderSkipsRungsBelowTheEntryVersion) {
  QJsonObject root = QJsonDocument::fromJson(R"({
    "schemaVersion": 4,
    "profiles": [{"id": "default", "tasks": [
      {"id": "T-1", "scheduledAt": "2026-07-08T14:30:00", "dueAt": "2026-07-08T18:00:00",
       "hasTime": true, "deadline": "2026-01-01"}
    ]}]
  })")
                         .object();

  // A v4 document is below the current version, so the ladder does run — but
  // only the rungs at or above 4. The v3→v4 rung consumes `deadline` and
  // rewrites scheduledAt/dueAt/hasTime; it must not touch this document.
  EXPECT_TRUE(heap::state::migrateState(root, 4));

  const QJsonObject task = root["profiles"].toArray().at(0).toObject()["tasks"].toArray().at(0).toObject();
  EXPECT_EQ(task["scheduledAt"].toString(), QStringLiteral("2026-07-08T14:30:00"))
      << "a rung below the entry version must not rewrite scheduledAt";
  EXPECT_TRUE(task["hasTime"].toBool()) << "a rung below the entry version must not clear hasTime";
  EXPECT_TRUE(task.contains(QStringLiteral("deadline"))) << "the v3->v4 rung consumes `deadline`; entering at v4 it must be left alone";
  // The v4→v5 rung, on the other hand, is at the entry version and does run.
  EXPECT_TRUE(task.contains(QStringLiteral("rank")));
}

// v4→v5: the board had no per-task order, so the order it showed was the array
// order. The migration has to freeze exactly that, spaced so a later drop
// between two cards has a midpoint to take.
TEST_F(MigrationTest, V4ToV5GivesEveryTaskARankInArrayOrder) {
  QJsonObject root = QJsonDocument::fromJson(R"({
    "schemaVersion": 4,
    "profiles": [{"id": "default", "tasks": [
      {"id": "T-1"}, {"id": "T-2"}, {"id": "T-3"}
    ]}]
  })")
                         .object();

  ASSERT_TRUE(heap::state::migrateState(root, 4));

  const QJsonArray tasks = root["profiles"].toArray().at(0).toObject()["tasks"].toArray();
  ASSERT_EQ(tasks.size(), 3);
  double previous = -1.0;
  for(const QJsonValue& v : tasks) {
    const double rank = v.toObject()["rank"].toDouble(-1.0);
    EXPECT_GT(rank, previous) << "ranks must ascend with the array order";
    previous = rank;
  }
  // Spaced, not 1/2/3: a midpoint insert must not immediately need a rebalance.
  EXPECT_GE(tasks.at(1).toObject()["rank"].toDouble() - tasks.at(0).toObject()["rank"].toDouble(), 2.0);
}

// A task that already carries a rank keeps it — the rung must not renumber a
// column that a newer build already ordered.
TEST_F(MigrationTest, V4ToV5KeepsAnExistingRank) {
  QJsonObject root = QJsonDocument::fromJson(R"({
    "schemaVersion": 4,
    "profiles": [{"id": "default", "tasks": [{"id": "T-1", "rank": 7.5}, {"id": "T-2"}]}]
  })")
                         .object();

  ASSERT_TRUE(heap::state::migrateState(root, 4));

  const QJsonArray tasks = root["profiles"].toArray().at(0).toObject()["tasks"].toArray();
  EXPECT_DOUBLE_EQ(tasks.at(0).toObject()["rank"].toDouble(), 7.5);
  EXPECT_GT(tasks.at(1).toObject()["rank"].toDouble(), 0.0);
}

// state.json written by a newer build: this one cannot represent the fields it
// did not parse, so it must never write over them.
TEST_F(MigrationTest, ANewerSchemaDisablesSavingAndKeepsTheFile) {
  QJsonObject root = QJsonDocument::fromJson(v3Document()).object();
  root["schemaVersion"] = heap::state::kSchemaVersion + 1;
  // A key this build knows nothing about — exactly what a save would drop.
  QJsonArray profiles = root["profiles"].toArray();
  QJsonObject p = profiles.at(0).toObject();
  p["notes"] = QJsonArray({QJsonObject{{"id", "N-1"}, {"title", "Inbox"}, {"body", "from the future"}}});
  profiles.replace(0, p);
  root["profiles"] = profiles;
  const QByteArray onDisk = QJsonDocument(root).toJson();
  writeFile(statePath(), onDisk);

  {
    AppController app;
    // Loaded best-effort: the user still sees their work.
    EXPECT_EQ(app.tasks()->rowCount(), 3);
    // Every save path is a no-op — the debounced scheduleSave() that saveTask
    // arms, and the direct flushSave() alike.
    QVariantMap draft = app.newTaskDraft(QStringLiteral("todo"));
    draft["title"] = QStringLiteral("this must not reach the disk");
    app.saveTask(draft);
    app.flushSave();
  }

  QFile f(statePath());
  ASSERT_TRUE(f.open(QIODevice::ReadOnly));
  EXPECT_EQ(f.readAll(), onDisk) << "a newer-schema file must be left byte-identical";

  const QJsonObject reread = readJson(statePath());
  EXPECT_EQ(reread["schemaVersion"].toInt(), heap::state::kSchemaVersion + 1);
  EXPECT_FALSE(reread["profiles"].toArray().at(0).toObject()["notes"].toArray().isEmpty()) << "the unknown field must survive";

  EXPECT_EQ(QDir(backupDir()).entryList({"state-premigration-*.json"}, QDir::Files).size(), 1)
      << "a copy is retained before the app touches anything";
}

// A failed first write leaves a v3 state.json on disk (QSaveFile never renamed).
// The next launch must find the retained pre-migration copy, not a partial file.
TEST_F(MigrationTest, MidMigrationFailureReopensToThePreMigrationBackup) {
  writeFile(statePath(), v3Document());

  {
    // The migration runs on load, then the debounced save is dropped on the
    // floor — the exact shape of a crash between migrate and commit.
    AppController::setStateWriterForTesting([](const QString&, const QByteArray&) {
      return false;
    });
    AppController app;
    app.flushSave();
    AppController::setStateWriterForTesting({});
  }

  // Simulate the crash having also damaged the live file.
  writeFile(statePath(), QByteArray("{ this is not json"));

  AppController reopened;
  ASSERT_EQ(reopened.tasks()->rowCount(), 3) << "must reopen to the pre-migration data, not a fresh seed";
  const Task* t = taskById(reopened, QStringLiteral("T-1"));
  ASSERT_NE(t, nullptr);
  EXPECT_EQ(t->dueAt.date(), QDate(2026, 7, 8));

  EXPECT_FALSE(QDir(appDataDir()).entryList({"state.corrupt-*.json"}, QDir::Files).isEmpty())
      << "the damaged file must be quarantined, never deleted";
}

// ── v7 → v8: notes stop being one blob ──
//
// Every note a profile ever held lived in one markdown string. Turning that
// into a list is the one migration in the ladder that must not lose anything:
// the blob IS the user's notes, and a key that no longer parses is the whole
// of Notes gone.

namespace {

QJsonObject migratedProfile(const QJsonValue& notesValue) {
  QJsonObject profile;
  profile["id"] = "demo";
  profile["name"] = "demo";
  profile["tasks"] = QJsonArray();
  if(!notesValue.isNull()) {
    profile["notes"] = notesValue;
  }
  QJsonObject root;
  root["schemaVersion"] = 7;
  root["profiles"] = QJsonArray{profile};
  heap::state::migrateState(root, 7);
  return root["profiles"].toArray().at(0).toObject();
}

}  // namespace

TEST(NotesMigration, TheOldBlobBecomesOneNote) {
  const QJsonObject p = migratedProfile(QString("# Standup notes\n\nremember the thing\n"));

  ASSERT_TRUE(p["notes"].isArray());
  const QJsonArray notes = p["notes"].toArray();
  ASSERT_EQ(notes.size(), 1);
  EXPECT_EQ(notes.at(0).toObject()["body"].toString(), QString("# Standup notes\n\nremember the thing\n"))
      << "not one character of it may be lost";
}

// The heading is what the user called it; a note with no name cannot be found
// in a list.
TEST(NotesMigration, TheFirstHeadingBecomesTheTitle) {
  const QJsonObject p = migratedProfile(QString("# Standup notes\n\nbody\n"));

  EXPECT_EQ(p["notes"].toArray().at(0).toObject()["title"].toString(), QString("Standup notes"));
}

TEST(NotesMigration, ABlobWithNoHeadingStillGetsAName) {
  const QJsonObject p = migratedProfile(QString("just some text with no heading\n"));

  EXPECT_FALSE(p["notes"].toArray().at(0).toObject()["title"].toString().isEmpty());
}

// The migrated note has to be the one that opens, or an upgrade looks like the
// notes are gone until the user goes looking for them.
TEST(NotesMigration, TheMigratedNoteIsTheActiveOne) {
  const QJsonObject p = migratedProfile(QString("# Title\n\nbody"));

  EXPECT_EQ(p["activeNoteId"].toString(), p["notes"].toArray().at(0).toObject()["id"].toString());
}

TEST(NotesMigration, AnEmptyBlobBecomesNoNotesRatherThanOneEmptyOne) {
  const QJsonObject p = migratedProfile(QString("   \n\n"));

  ASSERT_TRUE(p["notes"].isArray());
  EXPECT_EQ(p["notes"].toArray().size(), 0);
}

TEST(NotesMigration, AProfileWithNoNotesKeyIsLeftAlone) {
  const QJsonObject p = migratedProfile(QJsonValue::Null);

  EXPECT_FALSE(p.contains("notes"));
}

// Running the ladder twice must not wrap the array in another array, or turn
// the notes into a single note whose body is JSON.
TEST(NotesMigration, MigratingTwiceChangesNothing) {
  QJsonObject profile;
  profile["id"] = "demo";
  profile["notes"] = QString("# Title\n\nbody");
  QJsonObject root;
  root["schemaVersion"] = 7;
  root["profiles"] = QJsonArray{profile};

  heap::state::migrateState(root, 7);
  const QJsonArray once = root["profiles"].toArray().at(0).toObject()["notes"].toArray();
  heap::state::migrateState(root, heap::state::kSchemaVersion);
  const QJsonArray twice = root["profiles"].toArray().at(0).toObject()["notes"].toArray();

  EXPECT_EQ(once, twice);
}

// A file already written by v8 goes through the ladder untouched.
TEST(NotesMigration, AnArrayIsNotReMigrated) {
  QJsonObject note;
  note["id"] = "n-1";
  note["title"] = "kept";
  note["body"] = "body";
  QJsonObject profile;
  profile["id"] = "demo";
  profile["notes"] = QJsonArray{note};
  QJsonObject root;
  root["schemaVersion"] = 7;
  root["profiles"] = QJsonArray{profile};

  heap::state::migrateState(root, 7);

  const QJsonArray notes = root["profiles"].toArray().at(0).toObject()["notes"].toArray();
  ASSERT_EQ(notes.size(), 1);
  EXPECT_EQ(notes.at(0).toObject()["title"].toString(), QString("kept"));
}

// The reader has to cope with the old shape whether or not the ladder has run
// over the document yet — the same tolerance `deadline` has.
TEST(NotesMigration, TheReaderStillUnderstandsTheOldBlob) {
  QJsonObject profile;
  profile["id"] = "demo";
  profile["notes"] = QString("# Legacy\n\nstill here");

  const Profile p = heap::state::profileFromJson(profile, nullptr);

  EXPECT_TRUE(p.notes.isEmpty());
  EXPECT_EQ(p.notesState, QString("# Legacy\n\nstill here"));
}

TEST(NotesMigration, NotesSurviveARoundTrip) {
  Profile p;
  p.id = "demo";
  Note n;
  n.id = "n-1";
  n.title = "Title";
  n.folder = "meetings/2026";
  n.body = "# Title\n\nbody";
  n.pinned = true;
  n.created = QDateTime(QDate(2026, 1, 2), QTime(3, 4));
  n.updated = QDateTime(QDate(2026, 5, 6), QTime(7, 8));
  p.notes = {n};
  p.activeNoteId = "n-1";

  const Profile back = heap::state::profileFromJson(heap::state::profileToJson(p), nullptr);

  ASSERT_EQ(back.notes.size(), 1);
  EXPECT_EQ(back.notes.at(0), n);
  EXPECT_EQ(back.activeNoteId, QString("n-1"));
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
