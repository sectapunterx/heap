// Profiles written by released versions still open, intact, in this one.
//
// tests/fixtures/state/<version>.json is a state.json that the release <version>
// itself wrote: its own AppController, booted on a fresh test-mode profile (the
// demo seed) plus a typed note, saved by its own code — not a hand-written
// imitation of the format. One per schema generation that shipped: 3 (≤ 0.4.7),
// 4 (0.4.8–0.4.9) and 9 (0.5.x).
//
// Every fixture is opened by today's AppController and checked against the file
// itself: every task, event and person is still there under the same id and
// title, the note survives with its text, and after a save and a fresh launch
// nothing is lost a second time. A release that changes the schema adds its own
// fixture here (see tests/fixtures/state/README.md).
//
// Runs headless against QStandardPaths test mode, so it never touches the
// user's real AppDataLocation.

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

#include <algorithm>
#include <cctype>

namespace {

const QString kNoteMarker = QString::fromUtf8("Планёрка");

QString appDataDir() {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QString statePath() {
  return appDataDir() + "/state.json";
}

QJsonObject readJson(const QString& path) {
  QFile f(path);
  if(!f.open(QIODevice::ReadOnly)) {
    return {};
  }
  return QJsonDocument::fromJson(f.readAll()).object();
}

std::vector<std::string> fixtureNames() {
  std::vector<std::string> names;
  for(const QString& file : QDir(QStringLiteral(HEAP_STATE_FIXTURES_DIR)).entryList({"*.json"}, QDir::Files, QDir::Name)) {
    names.push_back(file.toStdString());
  }
  return names;
}

// id -> title of every entry in a JSON array of objects.
QMap<QString, QString> titlesById(const QJsonArray& items, const QString& titleKey) {
  QMap<QString, QString> out;
  for(const auto& v : items) {
    const QJsonObject o = v.toObject();
    out.insert(o.value("id").toString(), o.value(titleKey).toString());
  }
  return out;
}

template<typename Item>
QMap<QString, QString> titlesById(const QVector<Item>& items) {
  QMap<QString, QString> out;
  for(const Item& item : items) {
    out.insert(item.id, item.title);
  }
  return out;
}

QMap<QString, QString> namesById(const QVector<Person>& people) {
  QMap<QString, QString> out;
  for(const Person& p : people) {
    out.insert(p.id, p.name);
  }
  return out;
}

bool hasNoteWithMarker(AppController& app) {
  return std::ranges::any_of(app.notes()->items(), [](const Note& n) {
    return n.body.contains(kNoteMarker);
  });
}

class StateFixtureTest : public ::testing::TestWithParam<std::string> {
 protected:
  void SetUp() override {
    QDir(appDataDir()).removeRecursively();
    QDir().mkpath(appDataDir());
    const QString source = QStringLiteral(HEAP_STATE_FIXTURES_DIR "/") + QString::fromStdString(GetParam());
    ASSERT_TRUE(QFile::copy(source, statePath())) << source.toStdString();

    const QJsonObject root = readJson(source);
    schema_ = root.value("schemaVersion").toInt();
    const QJsonObject profile = root.value("profiles").toArray().at(0).toObject();
    tasks_ = titlesById(profile.value("tasks").toArray(), QStringLiteral("title"));
    // Events moved between the root and the profile across versions.
    events_ =
        titlesById(root.contains("events") ? root.value("events").toArray() : profile.value("events").toArray(), QStringLiteral("title"));
    people_ = titlesById(profile.value("people").toArray(), QStringLiteral("name"));
    ASSERT_FALSE(tasks_.isEmpty()) << "a fixture with no tasks checks nothing";
  }

  void TearDown() override {
    QDir(appDataDir()).removeRecursively();
  }

  // Everything the file had, the app has — ids and titles, not just counts.
  void expectEverythingFromTheFile(AppController& app) const {
    EXPECT_EQ(titlesById(app.tasks()->items()), tasks_);
    EXPECT_EQ(titlesById(app.events()->items()), events_);
    EXPECT_EQ(namesById(app.people()->items()), people_);
    EXPECT_TRUE(hasNoteWithMarker(app)) << "the typed note did not survive";
  }

  int schema_ = 0;
  QMap<QString, QString> tasks_;
  QMap<QString, QString> events_;
  QMap<QString, QString> people_;
};

}  // namespace

TEST_P(StateFixtureTest, OpensWithEverythingInIt) {
  AppController app;
  expectEverythingFromTheFile(app);
}

TEST_P(StateFixtureTest, SurvivesASaveAndTheNextLaunch) {
  {
    AppController app;
    app.flushSave();
  }
  if(schema_ < heap::state::kSchemaVersion) {
    EXPECT_EQ(readJson(statePath()).value("schemaVersion").toInt(), heap::state::kSchemaVersion)
        << "opening an older profile must upgrade the file";
  }
  AppController reopened;
  expectEverythingFromTheFile(reopened);
}

INSTANTIATE_TEST_SUITE_P(Releases,
                         StateFixtureTest,
                         ::testing::ValuesIn(fixtureNames()),
                         [](const ::testing::TestParamInfo<std::string>& info) {
                           std::string name = info.param.substr(0, info.param.rfind('.'));
                           for(char& c : name) {
                             c = std::isalnum(static_cast<unsigned char>(c)) ? c : '_';
                           }
                           return name;
                         });

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
