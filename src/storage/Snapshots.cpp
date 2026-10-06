#include "storage/Snapshots.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>

#include <algorithm>

namespace heap::history {

namespace {

constexpr char kMagic[] = "HEAPSNAP 1\n";
constexpr int kMagicLen = sizeof(kMagic) - 1;
// zlib level 1: a 10k-task state compresses ~8x either way, and level 1 is
// several times faster than the default 6 (measured in test_snapshots).
constexpr int kCompressionLevel = 1;

const QRegularExpression& nameRx() {
  static const QRegularExpression rx(QStringLiteral("^state-(\\d{8})-(\\d{4})(?:-([a-z]+))?(?:-(\\d+))?\\.json\\.z$"));
  return rx;
}

}  // namespace

Policy policyFrom(const QVariantMap& dataSettings) {
  Policy p;
  bool ok = false;
  const int days = dataSettings.value(QStringLiteral("historyDays")).toInt(&ok);
  p.dailyDays = ok && days > 0 ? std::clamp(days, 2, 365) : kDefaultDays;
  const int mb = dataSettings.value(QStringLiteral("historyMaxMb")).toInt(&ok);
  p.maxBytes = static_cast<qint64>(ok && mb > 0 ? std::clamp(mb, 10, 10000) : kDefaultMaxMb) * 1024 * 1024;
  return p;
}

QString dirFor(const QString& dataDir) {
  return dataDir + QStringLiteral("/history");
}

QString fileNameFor(const QDateTime& at, const QString& tag) {
  QString name = QStringLiteral("state-") + at.toString(QStringLiteral("yyyyMMdd-HHmm"));
  if(!tag.isEmpty()) {
    name += QLatin1Char('-') + tag;
  }
  return name + QStringLiteral(".json.z");
}

bool parseName(const QString& name, QDateTime* at, QString* tag) {
  const auto m = nameRx().match(name);
  if(!m.hasMatch()) {
    return false;
  }
  const QDateTime when = QDateTime::fromString(m.captured(1) + m.captured(2), QStringLiteral("yyyyMMddHHmm"));
  if(!when.isValid()) {
    return false;
  }
  if(at) {
    *at = when;
  }
  if(tag) {
    *tag = m.captured(3);
  }
  return true;
}

QVector<SnapshotFile> list(const QString& dir) {
  QVector<SnapshotFile> out;
  const QDir d(dir);
  const QFileInfoList infos = d.entryInfoList({QStringLiteral("state-*.json.z")}, QDir::Files | QDir::NoSymLinks);
  for(const QFileInfo& fi : infos) {
    SnapshotFile f;
    if(!parseName(fi.fileName(), &f.at, &f.tag)) {
      continue;
    }
    f.name = fi.fileName();
    f.bytes = fi.size();
    out.append(f);
  }
  std::sort(out.begin(), out.end(), [](const SnapshotFile& a, const SnapshotFile& b) {
    return a.at != b.at ? a.at > b.at : a.name > b.name;
  });
  return out;
}

bool isDue(const QVector<SnapshotFile>& existing, const QDateTime& now, qint64 minIntervalSecs) {
  QDateTime newest;
  for(const SnapshotFile& f : existing) {
    if(!f.tag.isEmpty()) {
      continue;  // a copy taken before a restore is not the hourly one
    }
    if(!newest.isValid() || f.at > newest) {
      newest = f.at;
    }
  }
  if(!newest.isValid()) {
    return true;
  }
  const qint64 age = newest.secsTo(now);
  return age < 0 || age >= minIntervalSecs;
}

QStringList pickToDelete(const QVector<SnapshotFile>& files, const QDateTime& now, const Policy& policy) {
  QVector<SnapshotFile> sorted = files;
  std::sort(sorted.begin(), sorted.end(), [](const SnapshotFile& a, const SnapshotFile& b) {
    return a.at != b.at ? a.at > b.at : a.name > b.name;
  });
  const qint64 hourlySecs = static_cast<qint64>(policy.hourlyHours) * 3600;
  const QDate oldestDay = now.date().addDays(-policy.dailyDays);

  QVector<SnapshotFile> kept;
  QStringList out;
  QSet<QString> hoursSeen;
  QSet<QDate> daysSeen;
  for(int i = 0; i < sorted.size(); ++i) {
    const SnapshotFile& f = sorted.at(i);
    const qint64 age = f.at.secsTo(now);
    bool keep = false;
    if(i == 0) {
      keep = true;  // whatever its age: the one copy there is
    } else if(age < hourlySecs) {
      // Newest first, so the first one seen in an hour is that hour's last.
      const QString hour = f.at.toString(QStringLiteral("yyyyMMddHH"));
      keep = !f.tag.isEmpty() || !hoursSeen.contains(hour);
      if(f.tag.isEmpty()) {
        hoursSeen.insert(hour);
      }
    } else if(f.at.date() > oldestDay) {
      keep = !daysSeen.contains(f.at.date());
    }
    daysSeen.insert(f.at.date());
    if(keep) {
      kept.append(f);
    } else {
      out.append(f.name);
    }
  }

  // The size cap takes the oldest of what is left; the newest always stays.
  qint64 total = 0;
  for(int i = 0; i < kept.size(); ++i) {
    total += kept.at(i).bytes;
    if(i > 0 && total > policy.maxBytes) {
      out.append(kept.at(i).name);
    }
  }
  return out;
}

QJsonObject summarize(const QJsonObject& stateRoot) {
  int tasks = 0;
  int notes = 0;
  int docs = 0;
  const QJsonArray profiles = stateRoot.value(QStringLiteral("profiles")).toArray();
  for(const auto& v : profiles) {
    const QJsonObject p = v.toObject();
    tasks += static_cast<int>(p.value(QStringLiteral("tasks")).toArray().size());
    notes += static_cast<int>(p.value(QStringLiteral("notes")).toArray().size());
    docs += static_cast<int>(p.value(QStringLiteral("docPages")).toArray().size());
  }
  return QJsonObject{{QStringLiteral("schema"), stateRoot.value(QStringLiteral("schemaVersion")).toInt()},
                     {QStringLiteral("profiles"), static_cast<int>(profiles.size())},
                     {QStringLiteral("tasks"), tasks},
                     {QStringLiteral("notes"), notes},
                     {QStringLiteral("docs"), docs},
                     {QStringLiteral("events"), static_cast<int>(stateRoot.value(QStringLiteral("events")).toArray().size())}};
}

QByteArray encode(const QByteArray& stateJson, const QJsonObject& summary) {
  QByteArray out(kMagic, kMagicLen);
  out += QJsonDocument(summary).toJson(QJsonDocument::Compact);
  out += '\n';
  out += qCompress(stateJson, kCompressionLevel);
  return out;
}

bool decode(const QByteArray& fileBytes, QByteArray* stateJson, QJsonObject* summary) {
  if(!fileBytes.startsWith(QByteArray(kMagic, kMagicLen))) {
    return false;
  }
  const qsizetype eol = fileBytes.indexOf('\n', kMagicLen);
  if(eol < 0) {
    return false;
  }
  if(summary) {
    *summary = QJsonDocument::fromJson(fileBytes.mid(kMagicLen, eol - kMagicLen)).object();
  }
  if(stateJson) {
    *stateJson = qUncompress(fileBytes.mid(eol + 1));
    if(stateJson->isEmpty()) {
      return false;
    }
  }
  return true;
}

QJsonObject readSummary(const QString& path) {
  QFile f(path);
  if(!f.open(QIODevice::ReadOnly)) {
    return {};
  }
  if(f.read(kMagicLen) != QByteArray(kMagic, kMagicLen)) {
    return {};
  }
  return QJsonDocument::fromJson(f.readLine(4096).trimmed()).object();
}

QByteArray read(const QString& path, QString* error) {
  QFile f(path);
  if(!f.open(QIODevice::ReadOnly)) {
    if(error) {
      *error = f.errorString();
    }
    return {};
  }
  QByteArray state;
  if(!decode(f.readAll(), &state)) {
    if(error) {
      *error = QStringLiteral("not a heap snapshot, or damaged");
    }
    return {};
  }
  return state;
}

QString write(
    const QString& dir, const QByteArray& stateJson, const QJsonObject& summary, const QDateTime& at, const QString& tag, QString* error) {
  if(!QDir().mkpath(dir)) {
    if(error) {
      *error = QStringLiteral("cannot create ") + dir;
    }
    return {};
  }
  QString name = fileNameFor(at, tag);
  const QString stem = name.chopped(7);  // without ".json.z"
  for(int n = 2; QFile::exists(dir + QLatin1Char('/') + name); ++n) {
    name = stem + QLatin1Char('-') + QString::number(n) + QStringLiteral(".json.z");
  }
  QSaveFile f(dir + QLatin1Char('/') + name);
  if(!f.open(QIODevice::WriteOnly)) {
    if(error) {
      *error = f.errorString();
    }
    return {};
  }
  const QByteArray bytes = encode(stateJson, summary);
  if(f.write(bytes) != bytes.size()) {
    if(error) {
      *error = f.errorString();
    }
    f.cancelWriting();
    return {};
  }
  if(!f.commit()) {
    if(error) {
      *error = f.errorString();
    }
    return {};
  }
  return name;
}

int prune(const QString& dir, const QDateTime& now, const Policy& policy) {
  int removed = 0;
  QDir d(dir);
  for(const QString& name : pickToDelete(list(dir), now, policy)) {
    removed += d.remove(name) ? 1 : 0;
  }
  return removed;
}

QString maybeSnapshot(
    const QString& dir, const QByteArray& stateJson, const QJsonObject& summary, const QDateTime& now, const Policy& policy) {
  if(!isDue(list(dir), now, policy.minIntervalSecs)) {
    return {};
  }
  const QString name = write(dir, stateJson, summary, now);
  prune(dir, now, policy);
  return name;
}

}  // namespace heap::history
