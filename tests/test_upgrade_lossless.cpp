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
#include <functional>

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

bool idArray(const QJsonValue& v) {
  if(!v.isArray() || v.toArray().isEmpty()) {
    return false;
  }
  for(const auto& e : v.toArray()) {
    if(!e.isObject() || e.toObject().value("id").toString().isEmpty()) {
      return false;
    }
  }
  return true;
}

// Each key of `before` is in `after` with the same value; a tracker card may
// have moved its local divergence into `local`. Objects and arrays of id'd
// objects (columns, people) are compared key by key, so a key v12 adds to
// them (a column's stage) is not a loss.
void expectKept(const QJsonObject& before, const QJsonObject& after, const QString& where, bool trackerCard) {
  for(auto it = before.begin(); it != before.end(); ++it) {
    const QJsonValue now = after.value(it.key());
    if(now == it.value()) {
      continue;
    }
    if(it.value().isObject() && now.isObject()) {
      expectKept(it.value().toObject(), now.toObject(), where + "/" + it.key(), false);
      continue;
    }
    if(idArray(it.value()) && idArray(now)) {
      const QJsonObject was = byId(it.value().toArray());
      const QJsonObject is = byId(now.toArray());
      for(auto e = was.begin(); e != was.end(); ++e) {
        if(!is.contains(e.key())) {
          ADD_FAILURE() << where.toStdString() << "/" << it.key().toStdString() << "/" << e.key().toStdString() << " is gone";
          continue;
        }
        expectKept(e.value().toObject(), is.value(e.key()).toObject(), where + "/" + it.key() + "/" + e.key(), false);
      }
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

// The demo seed a 0.7.2 fixture holds has no keys a newer build wrote, no
// rebound keys, no timer and no tracker card. Here the same file gets all of
// them, the way a real 0.7.x profile has them, and the whole document has to
// come through the upgrade and the next launch.
namespace {

QJsonArray withFirst(QJsonArray a, const std::function<void(QJsonObject&)>& edit) {
  QJsonObject o = a.at(0).toObject();
  edit(o);
  a[0] = o;
  return a;
}

QString sequenceIn(AppController& app, const QString& id) {
  for(const QVariant& v : app.shortcuts()) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("id")).toString() == id) {
      return m.value(QStringLiteral("sequence")).toString();
    }
  }
  return {};
}

QJsonObject richV11() {
  QJsonObject root = readJson(QStringLiteral(HEAP_STATE_FIXTURES_DIR "/v0.7.2.json"));
  const QJsonObject later{{"from", "a later build"}};
  root["laterRootKey"] = later;

  QJsonObject settings = root.value("settings").toObject();
  settings["laterSetting"] = later;
  // Rebound in 0.7.2: one moved to a key of its own, one cleared on purpose.
  settings["shortcuts"] = QJsonObject{{"theme.toggle", "Ctrl+Shift+Y"}, {"task.openExternal", ""}};
  settings["shortcutsSchema"] = 2;
  root["settings"] = settings;

  root["events"] = withFirst(root.value("events").toArray(), [&](QJsonObject& e) {
    e["laterEventKey"] = later;
  });

  root["profiles"] = withFirst(root.value("profiles").toArray(), [&](QJsonObject& p) {
    p["laterProfileKey"] = later;
    p["people"] = withFirst(p.value("people").toArray(), [&](QJsonObject& o) {
      o["laterPersonKey"] = later;
    });
    p["statuses"] = withFirst(p.value("statuses").toArray(), [&](QJsonObject& o) {
      o["laterStatusKey"] = later;
    });
    QJsonArray tasks = withFirst(p.value("tasks").toArray(), [&](QJsonObject& t) {
      t["laterTaskKey"] = later;
      t["trackedSeconds"] = 5400;  // the 0.7 timer's one total
    });
    // A tracker card edited here: its local values move into `local`.
    QJsonObject card = tasks.at(1).toObject();
    card["id"] = QStringLiteral("t-tracker-card");
    card["rank"] = 1.0e9;  // its own place, not a tie with the card it was copied from
    card["externalId"] = QStringLiteral("10042");
    card["externalUrl"] = QStringLiteral("https://example.atlassian.net/browse/PROJ-42");
    card["externalProvider"] = QStringLiteral("jira");
    card["title"] = QStringLiteral("My own title");
    card["desc"] = QStringLiteral("My own notes on it");
    card["priority"] = QStringLiteral("P0");
    card["externalMeta"] =
        QJsonObject{{"remoteTitle", "The tracker's title"}, {"remoteBody", "The tracker's body"}, {"remotePriority", "P2"}};
    tasks.append(card);
    p["tasks"] = tasks;
  });
  return root;
}

void writeState(const QJsonObject& root) {
  QDir(appDataDir()).removeRecursively();
  QDir().mkpath(appDataDir());
  QFile f(appDataDir() + "/state.json");
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write(QJsonDocument(root).toJson());
}

}  // namespace

TEST(UpgradeLosslessRich, AFullV11ProfileComesThroughTheUpgradeAndTheNextLaunch) {
  const QJsonObject before = richV11();
  writeState(before);
  {
    AppController app;
    EXPECT_EQ(sequenceIn(app, QStringLiteral("theme.toggle")), QStringLiteral("Ctrl+Shift+Y")) << "a rebind stays the user's";
    EXPECT_TRUE(sequenceIn(app, QStringLiteral("task.openExternal")).isEmpty()) << "a cleared binding stays cleared";
    app.flushSave();
  }
  const QJsonObject after = readJson(appDataDir() + "/state.json");
  ASSERT_EQ(after.value("schemaVersion").toInt(), heap::state::kSchemaVersion);

  // Whatever a later build wrote, at every level, is still there.
  EXPECT_EQ(after.value("laterRootKey"), before.value("laterRootKey"));
  const QJsonObject settings = after.value("settings").toObject();
  EXPECT_EQ(settings.value("laterSetting"), before.value("laterRootKey"));
  const QJsonObject shortcuts = settings.value("shortcuts").toObject();
  EXPECT_EQ(shortcuts.value("theme.toggle").toString(), QStringLiteral("Ctrl+Shift+Y"));
  EXPECT_TRUE(shortcuts.contains("task.openExternal") && shortcuts.value("task.openExternal").toString().isEmpty());
  EXPECT_EQ(after.value("events").toArray().at(0).toObject().value("laterEventKey"), before.value("laterRootKey"));

  QJsonObject pb = before.value("profiles").toArray().at(0).toObject();
  QJsonObject pa = after.value("profiles").toArray().at(0).toObject();
  EXPECT_EQ(pa.value("laterProfileKey"), before.value("laterRootKey"));
  const QJsonArray firstTasks = pb.value("tasks").toArray();
  const QJsonObject tasksBefore = byId(pb.take("tasks").toArray());
  const QJsonObject tasksAfter = byId(pa.take("tasks").toArray());
  expectKept(pb, pa, QStringLiteral("profiles/0"), false);
  ASSERT_EQ(tasksBefore.keys(), tasksAfter.keys());
  for(auto it = tasksBefore.begin(); it != tasksBefore.end(); ++it) {
    const QJsonObject t = it.value().toObject();
    expectKept(t, tasksAfter.value(it.key()).toObject(), "tasks/" + it.key(), !t.value("externalId").toString().isEmpty());
  }

  const QJsonObject timed = tasksAfter.value(firstTasks.at(0).toObject().value("id").toString()).toObject();
  EXPECT_EQ(timed.value("trackedSeconds").toInt(), 5400);
  EXPECT_EQ(timed.value("local").toObject().value("sessions").toArray().at(0).toObject().value("seconds").toInt(), 5400)
      << "the old total is one session before 0.8.0";

  const QJsonObject card = tasksAfter.value("t-tracker-card").toObject();
  EXPECT_EQ(card.value("title").toString(), QStringLiteral("The tracker's title"));
  EXPECT_EQ(card.value("priority").toString(), QStringLiteral("P2"));
  const QJsonObject local = card.value("local").toObject();
  EXPECT_EQ(local.value("myPriority").toString(), QStringLiteral("P0"));
  EXPECT_TRUE(local.value("notes").toString().contains(QStringLiteral("My own title")));
  EXPECT_TRUE(local.value("notes").toString().contains(QStringLiteral("My own notes on it")));

  // The next launch reads the v12 file and writes it back unchanged: the rung
  // ran once and does not run again.
  {
    AppController app;
    EXPECT_EQ(sequenceIn(app, QStringLiteral("theme.toggle")), QStringLiteral("Ctrl+Shift+Y"));
    app.flushSave();
  }
  QJsonObject again = readJson(appDataDir() + "/state.json");
  QJsonObject first = after;
  for(QJsonObject* doc : {&again, &first}) {
    doc->remove("taskHistory");  // a log of this run, not the user's data
  }
  EXPECT_EQ(QJsonDocument(again).toJson().toStdString(), QJsonDocument(first).toJson().toStdString());
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
