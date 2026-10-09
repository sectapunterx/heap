// Upgrading 0.7.x → 0.8.0 loses nothing (APP-244, owner's rule 2026-10-08).
//
// Every v11 state.json under tests/fixtures/state is opened by today's
// AppController, saved at v12, and compared key by key with the file it came
// from: each key the v11 file had is still there with the same value. The one
// allowed difference is a tracker card's local divergence, which the v11→v12
// rung moves into `local` — and then the old value has to be found there.
//
// HEAP_UPGRADE_PROFILE=<path to a state.json> runs the same check on a copy of
// a real profile (never committed; see tests/fixtures/state/README.md).

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

#include <gtest/gtest.h>

#include <cctype>

namespace {

QString appDataDir() {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QJsonObject readJson(const QString& path) {
  QFile f(path);
  return f.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(f.readAll()).object() : QJsonObject();
}

std::vector<std::string> sources() {
  std::vector<std::string> out;
  const QDir dir(QStringLiteral(HEAP_STATE_FIXTURES_DIR));
  for(const QString& f : dir.entryList({"*.json"}, QDir::Files, QDir::Name)) {
    if(readJson(dir.filePath(f)).value("schemaVersion").toInt() == 11) {
      out.push_back(dir.filePath(f).toStdString());
    }
  }
  const QString real = qEnvironmentVariable("HEAP_UPGRADE_PROFILE");
  if(!real.isEmpty()) {
    out.push_back(real.toStdString());
  }
  return out;
}

QJsonObject byId(const QJsonArray& a) {
  QJsonObject out;
  for(const auto& v : a) {
    out.insert(v.toObject().value("id").toString(), v);
  }
  return out;
}

// Where a moved value must turn up after the rung, per tracker field.
bool movedIntoLocal(const QString& key, const QJsonValue& was, const QJsonObject& after) {
  const QJsonObject local = after.value("local").toObject();
  if(key == QLatin1String("priority")) {
    return local.value("myPriority") == was;
  }
  if(key == QLatin1String("dueAt")) {
    return local.value("myDueAt") == was;
  }
  if(key == QLatin1String("dueHasTime")) {
    return local.value("myDueHasTime") == was;
  }
  if(key == QLatin1String("title") || key == QLatin1String("desc")) {
    return local.value("notes").toString().contains(was.toString());
  }
  if(key == QLatin1String("labels")) {
    QStringList all;
    for(const auto& l : after.value("labels").toArray()) {
      all << l.toObject().value("id").toString();
    }
    for(const auto& l : local.value("tags").toArray()) {
      all << l.toObject().value("id").toString();
    }
    for(const auto& l : was.toArray()) {
      if(!all.contains(l.toObject().value("id").toString())) {
        return false;
      }
    }
    return true;
  }
  return key == QLatin1String("externalMeta");  // its `conflicts` may shrink
}

// Each key of `before` is in `after` with the same value; a tracker card may
// have moved its local divergence into `local`.
void expectKept(const QJsonObject& before, const QJsonObject& after, const QString& where, bool trackerCard) {
  for(auto it = before.begin(); it != before.end(); ++it) {
    const QJsonValue now = after.value(it.key());
    if(now == it.value()) {
      continue;
    }
    // An empty value the reader fills in (a blank statusChangedAt becomes
    // "now", as in every version before) loses nothing.
    if(it.value().toString().isEmpty() && it.value().isString()) {
      continue;
    }
    if(trackerCard && movedIntoLocal(it.key(), it.value(), after)) {
      continue;
    }
    ADD_FAILURE() << where.toStdString() << "/" << it.key().toStdString() << " changed: "
                  << QJsonDocument(QJsonObject{{"was", it.value()}, {"now", now}}).toJson(QJsonDocument::Compact).toStdString();
  }
}

class UpgradeLossless : public ::testing::TestWithParam<std::string> {};

TEST_P(UpgradeLossless, EveryV11KeyIsStillThere) {
  const QString source = QString::fromStdString(GetParam());
  QDir(appDataDir()).removeRecursively();
  QDir().mkpath(appDataDir());
  ASSERT_TRUE(QFile::copy(source, appDataDir() + "/state.json"));
  {
    AppController app;
    app.flushSave();
  }
  const QJsonObject before = readJson(source);
  const QJsonObject after = readJson(appDataDir() + "/state.json");
  ASSERT_EQ(after.value("schemaVersion").toInt(), heap::state::kSchemaVersion);

  const QJsonObject eventsBefore = byId(before.value("events").toArray());
  const QJsonObject eventsAfter = byId(after.value("events").toArray());
  for(auto it = eventsBefore.begin(); it != eventsBefore.end(); ++it) {
    expectKept(it.value().toObject(), eventsAfter.value(it.key()).toObject(), "events/" + it.key(), false);
  }

  const QJsonObject profilesBefore = byId(before.value("profiles").toArray());
  const QJsonObject profilesAfter = byId(after.value("profiles").toArray());
  ASSERT_EQ(profilesBefore.keys(), profilesAfter.keys());
  for(auto pit = profilesBefore.begin(); pit != profilesBefore.end(); ++pit) {
    QJsonObject pb = pit.value().toObject();
    QJsonObject pa = profilesAfter.value(pit.key()).toObject();
    const QJsonObject tasksBefore = byId(pb.take("tasks").toArray());
    const QJsonObject tasksAfter = byId(pa.take("tasks").toArray());
    expectKept(pb, pa, "profiles/" + pit.key(), false);
    ASSERT_EQ(tasksBefore.keys(), tasksAfter.keys()) << pit.key().toStdString();
    for(auto tit = tasksBefore.begin(); tit != tasksBefore.end(); ++tit) {
      const QJsonObject t = tit.value().toObject();
      expectKept(t,
                 tasksAfter.value(tit.key()).toObject(),
                 "profiles/" + pit.key() + "/tasks/" + tit.key(),
                 !t.value("externalId").toString().isEmpty());
    }
  }

  // And a second launch reads the v12 file back to the same bytes.
  QFile first(appDataDir() + "/state.json");
  ASSERT_TRUE(first.open(QIODevice::ReadOnly));
  const QByteArray v12 = first.readAll();
  first.close();
  {
    AppController app;
    app.flushSave();
  }
  const QJsonObject again = readJson(appDataDir() + "/state.json");
  EXPECT_EQ(again.value("profiles"), QJsonDocument::fromJson(v12).object().value("profiles"));
}

INSTANTIATE_TEST_SUITE_P(Profiles, UpgradeLossless, ::testing::ValuesIn(sources()), [](const auto& info) {
  std::string name = QFileInfo(QString::fromStdString(info.param)).completeBaseName().toStdString();
  for(char& c : name) {
    if(!std::isalnum(static_cast<unsigned char>(c))) {
      c = '_';
    }
  }
  return name;
});

}  // namespace

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QStandardPaths::setTestModeEnabled(true);
  QApplication qapp(argc, argv);
  ::testing::InitGoogleTest(&argc, argv);
  const int rc = RUN_ALL_TESTS();
  QDir(appDataDir()).removeRecursively();
  return rc;
}
