// The opt-in completion sound (APP-167): when it plays, that the bundled WAV
// is a short, valid PCM file, and that only the user's own move to Done in the
// window asks for it — not a CLI request, an undo, or a move with the setting
// off. Playback itself is a no-op in QStandardPaths test mode, so the suite
// counts requests (completionSoundRequestCount) instead of listening.

#include "AppController.h"
#include "Models.h"

#include "cli/CliExecutor.h"
#include "platform/Sound.h"

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QtEndian>

#include <gtest/gtest.h>

#include <memory>

using heap::platform::shouldPlayCompletionSound;
using heap::platform::StatusChangeSource;

// ─── the pure decision ───────────────────────────────────────────────

TEST(CompletionSoundDecision, PlaysOnlyForTheUsersOwnMoveIntoDone) {
  EXPECT_TRUE(shouldPlayCompletionSound(QStringLiteral("todo"), QStringLiteral("done"), StatusChangeSource::User, true));
  EXPECT_TRUE(shouldPlayCompletionSound(QStringLiteral("prog"), QStringLiteral("done"), StatusChangeSource::User, true));
}

TEST(CompletionSoundDecision, OffByTheSetting) {
  EXPECT_FALSE(shouldPlayCompletionSound(QStringLiteral("todo"), QStringLiteral("done"), StatusChangeSource::User, false));
}

TEST(CompletionSoundDecision, QuietForSyncUndoAndCli) {
  for(const StatusChangeSource s : {StatusChangeSource::Sync, StatusChangeSource::Undo, StatusChangeSource::Cli}) {
    EXPECT_FALSE(shouldPlayCompletionSound(QStringLiteral("todo"), QStringLiteral("done"), s, true));
  }
}

TEST(CompletionSoundDecision, QuietWhenNotEnteringDone) {
  EXPECT_FALSE(shouldPlayCompletionSound(QStringLiteral("done"), QStringLiteral("done"), StatusChangeSource::User, true));
  EXPECT_FALSE(shouldPlayCompletionSound(QStringLiteral("done"), QStringLiteral("todo"), StatusChangeSource::User, true));
  EXPECT_FALSE(shouldPlayCompletionSound(QStringLiteral("todo"), QStringLiteral("prog"), StatusChangeSource::User, true));
}

// ─── the bundled asset ───────────────────────────────────────────────

TEST(CompletionSoundAsset, IsAShortMonoPcmWave) {
  const QByteArray& wav = heap::platform::completionSoundWav();
  ASSERT_GE(wav.size(), 44);
  EXPECT_LT(wav.size(), 15 * 1024);
  const auto* d = reinterpret_cast<const uchar*>(wav.constData());
  EXPECT_EQ(wav.left(4), QByteArray("RIFF"));
  EXPECT_EQ(wav.mid(8, 4), QByteArray("WAVE"));
  EXPECT_EQ(wav.mid(12, 4), QByteArray("fmt "));
  EXPECT_EQ(qFromLittleEndian<quint16>(d + 20), 1);  // PCM
  EXPECT_EQ(qFromLittleEndian<quint16>(d + 22), 1);  // mono
  const quint32 rate = qFromLittleEndian<quint32>(d + 24);
  EXPECT_EQ(rate, 44100U);
  EXPECT_EQ(qFromLittleEndian<quint16>(d + 34), 16);  // bits per sample
  EXPECT_EQ(wav.mid(36, 4), QByteArray("data"));
  const quint32 dataBytes = qFromLittleEndian<quint32>(d + 40);
  EXPECT_EQ(static_cast<qsizetype>(dataBytes) + 44, wav.size());
  const double seconds = static_cast<double>(dataBytes) / 2.0 / rate;
  EXPECT_GT(seconds, 0.05);
  EXPECT_LT(seconds, 0.25);
}

TEST(CompletionSoundPlayback, IsANoOpInTestMode) {
  ASSERT_TRUE(QStandardPaths::isTestModeEnabled());
  const int before = heap::platform::completionSoundRequestCount();
  heap::platform::playCompletionSound();  // must return at once, silently
  EXPECT_EQ(heap::platform::completionSoundRequestCount(), before + 1);
}

// ─── AppController wiring ────────────────────────────────────────────

namespace {

Task makeTask(const QString& id, const QString& status) {
  Task t;
  t.id = id;
  t.title = id + QStringLiteral(" title");
  t.priority = QStringLiteral("P2");
  t.status = status;
  return t;
}

}  // namespace

class CompletionSoundWiring : public ::testing::Test {
 protected:
  void SetUp() override {
    app_ = std::make_unique<AppController>();
    app_->tasks()->reset({makeTask(QStringLiteral("S-1"), QStringLiteral("todo")),
                          makeTask(QStringLiteral("S-2"), QStringLiteral("todo")),
                          makeTask(QStringLiteral("S-3"), QStringLiteral("prog"))});
  }

  void TearDown() override {
    app_.reset();
  }

  void setSoundEnabled(bool on) {
    QJsonObject root = QJsonDocument::fromJson(app_->appSettingsJson().toUtf8()).object();
    QJsonObject appearance = root.value(QStringLiteral("appearance")).toObject();
    appearance.insert(QStringLiteral("completionSound"), on);
    root.insert(QStringLiteral("appearance"), appearance);
    app_->setAppSettingsJson(QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact)));
  }

  QString statusOf(const QString& id) const {
    return app_->tasks()->items().at(app_->tasks()->indexOfId(id)).status;
  }

  static int requests() {
    return heap::platform::completionSoundRequestCount();
  }

  std::unique_ptr<AppController> app_;
};

TEST_F(CompletionSoundWiring, OffByDefault) {
  const int before = requests();
  app_->moveTask(QStringLiteral("S-1"), QStringLiteral("done"));
  ASSERT_EQ(statusOf(QStringLiteral("S-1")), QStringLiteral("done"));
  EXPECT_EQ(requests(), before);
}

TEST_F(CompletionSoundWiring, UserMoveToDoneAsksOnce) {
  setSoundEnabled(true);
  const int before = requests();
  app_->moveTask(QStringLiteral("S-1"), QStringLiteral("prog"));
  EXPECT_EQ(requests(), before);
  app_->moveTask(QStringLiteral("S-1"), QStringLiteral("done"));
  EXPECT_EQ(requests(), before + 1);
}

TEST_F(CompletionSoundWiring, EditorStatusChangeCounts) {
  setSoundEnabled(true);
  const int before = requests();
  QVariantMap draft = app_->taskById(QStringLiteral("S-3"));
  draft[QStringLiteral("status")] = QStringLiteral("done");
  ASSERT_TRUE(app_->saveTask(draft));
  ASSERT_EQ(statusOf(QStringLiteral("S-3")), QStringLiteral("done"));
  EXPECT_EQ(requests(), before + 1);
}

TEST_F(CompletionSoundWiring, UndoAndRedoStayQuiet) {
  setSoundEnabled(true);
  app_->moveTask(QStringLiteral("S-1"), QStringLiteral("done"));
  const int before = requests();
  app_->undo();
  ASSERT_EQ(statusOf(QStringLiteral("S-1")), QStringLiteral("todo"));
  app_->redo();
  ASSERT_EQ(statusOf(QStringLiteral("S-1")), QStringLiteral("done"));
  EXPECT_EQ(requests(), before);
}

TEST_F(CompletionSoundWiring, BulkMoveTicksOnce) {
  setSoundEnabled(true);
  const int before = requests();
  app_->setSelectedTaskIds({QStringLiteral("S-1"), QStringLiteral("S-2"), QStringLiteral("S-3")});
  app_->moveSelectedTasksToStatus(QStringLiteral("done"));
  ASSERT_EQ(statusOf(QStringLiteral("S-2")), QStringLiteral("done"));
  EXPECT_EQ(requests(), before + 1);
}

TEST_F(CompletionSoundWiring, CliDoneStaysQuiet) {
  setSoundEnabled(true);
  const int before = requests();
  heap::cli::Request request;
  request.verb = heap::cli::Verb::Done;
  request.taskId = QStringLiteral("S-1");
  const heap::cli::Response r = heap::cli::execute(*app_, request, QDateTime::currentDateTime());
  EXPECT_EQ(r.exitCode, 0);
  ASSERT_EQ(statusOf(QStringLiteral("S-1")), QStringLiteral("done"));
  EXPECT_EQ(requests(), before);
  // …and the next move in the window is heard again.
  app_->moveTask(QStringLiteral("S-2"), QStringLiteral("done"));
  EXPECT_EQ(requests(), before + 1);
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QTemporaryDir scratch;
  scratch.setAutoRemove(true);
  qputenv("XDG_CONFIG_HOME", scratch.path().toUtf8());
  qputenv("XDG_DATA_HOME", scratch.path().toUtf8());

  QApplication qapp(argc, argv);

  const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  if(!appData.isEmpty()) {
    QFile::remove(appData + QStringLiteral("/state.json"));
    QDir(appData + QStringLiteral("/backups")).removeRecursively();
  }

  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
