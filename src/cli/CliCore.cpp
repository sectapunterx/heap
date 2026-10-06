#include "StateSerializer.h"
#include "ViewNames.h"

#include "cli/CliCore.h"
#include "git/BranchTaskMatcher.h"
#include "git/BranchTaskResolve.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QVariantMap>

#include <algorithm>

namespace heap::cli {

namespace {

struct VerbName {
  const char* name;
  Verb verb;
};

constexpr VerbName kVerbNames[] = {
    {"add", Verb::Add},
    {"now", Verb::Now},
    {"list", Verb::List},
    {"today", Verb::Today},
    {"done", Verb::Done},
    {"open", Verb::Open},
    {"help", Verb::Help},
};

QString verbName(Verb v) {
  for(const VerbName& n : kVerbNames) {
    if(n.verb == v) {
      return QString::fromLatin1(n.name);
    }
  }
  return v == Verb::Version ? QStringLiteral("version") : QStringLiteral("help");
}

std::optional<Verb> verbFromName(const QString& name) {
  for(const VerbName& n : kVerbNames) {
    if(name == QLatin1String(n.name)) {
      return n.verb;
    }
  }
  if(name == QLatin1String("version")) {
    return Verb::Version;
  }
  return std::nullopt;
}

ParsedArgs fail(const QString& error) {
  ParsedArgs p;
  p.error = error;
  return p;
}

}  // namespace

QString helpText() {
  return QStringLiteral(
             "heap - keyboard-first tickets, planning and notes for engineers.\n"
             "\n"
             "Usage:\n"
             "  heap [--view <name>] [--data-dir <dir>]   open the window (or bring it forward)\n"
             "  heap <command> [options]                  answer on the command line\n"
             "\n"
             "Commands:\n"
             "  add \"<text>\" [--profile <p>] [--json]   capture a task, read like quick capture:\n"
             "                                          dates (\"tomorrow 14:00\"), p1 / !!, #label,\n"
             "                                          \"// description\", a tracker key as the id\n"
             "  now [--json] [--format \"<fmt>\"]         the current task: the one with a running\n"
             "                                          timer, else the one the git branch of the\n"
             "                                          current directory names; prints nothing\n"
             "                                          when there is none. Format fields: {id}\n"
             "                                          {title} {status} {priority} {profile}\n"
             "                                          {source} {elapsed}\n"
             "  list [--profile <p>] [--status <s>] [--json]\n"
             "                                          tasks in board order (archived left out)\n"
             "  today [--profile <p>] [--json]          in progress, or scheduled or due today\n"
             "  done <ID>                               move a task to Done\n"
             "  open <ID>                               show the task in the window\n"
             "  help                                    this text\n"
             "\n"
             "Options:\n"
             "  --data-dir <dir>   use the profile kept in <dir> (also HEAP_DATA_DIR)\n"
             "  --profile <p>      a profile name or id instead of the active one\n"
             "  --json             machine-readable output\n"
             "  --view <name>      open <name> instead of the last used view: %1\n"
             "  --smoke            load the UI against a throwaway profile and exit (0 = healthy)\n"
             "  -h, --help         this text\n"
             "  -v, --version      the version\n"
             "\n"
             "With heap open on the same data directory, commands go to the window, so\n"
             "a change shows up there at once and can be undone there.\n"
             "\n"
             "Exit codes: 0 ok, 1 usage, 2 not found, 3 data error.\n")
      .arg(heap::views::all().join(QStringLiteral(", ")));
}

ParsedArgs parseArgs(const QStringList& args) {
  QCommandLineParser parser;
  parser.setOptionsAfterPositionalArgumentsMode(QCommandLineParser::ParseAsOptions);
  const QCommandLineOption help({QStringLiteral("h"), QStringLiteral("help"), QStringLiteral("?")}, QString());
  const QCommandLineOption version({QStringLiteral("v"), QStringLiteral("version")}, QString());
  const QCommandLineOption dataDir(QStringLiteral("data-dir"), QString(), QStringLiteral("dir"));
  const QCommandLineOption profile(QStringLiteral("profile"), QString(), QStringLiteral("profile"));
  const QCommandLineOption status(QStringLiteral("status"), QString(), QStringLiteral("status"));
  const QCommandLineOption format(QStringLiteral("format"), QString(), QStringLiteral("format"));
  const QCommandLineOption json(QStringLiteral("json"), QString());
  // Window-launch switches that may ride along with --help/--version; known
  // here so they are not refused, and otherwise ignored.
  const QCommandLineOption perfLog(QStringLiteral("perf-log"), QString());
  const QCommandLineOption capture(QStringLiteral("capture"), QString());
  const QCommandLineOption minimized(QStringLiteral("minimized"), QString());
  parser.addOptions({help, version, dataDir, profile, status, format, json, perfLog, capture, minimized});

  QStringList withProgram = args;
  withProgram.prepend(QStringLiteral("heap"));
  if(!parser.parse(withProgram)) {
    return fail(parser.errorText());
  }

  ParsedArgs out;
  out.dataDirSet = parser.isSet(dataDir);
  out.dataDir = parser.value(dataDir);
  // `--data-dir ""` (an unset shell variable) must never mean "the real
  // profile" — keeping a run away from it is what the flag is for (PLAT-22).
  if(out.dataDirSet && out.dataDir.trimmed().isEmpty()) {
    return fail(QStringLiteral("--data-dir needs a directory"));
  }

  QStringList positional = parser.positionalArguments();
  Request& r = out.request;
  if(positional.isEmpty()) {
    if(parser.isSet(version)) {
      r.verb = Verb::Version;
    } else if(parser.isSet(help)) {
      r.verb = Verb::Help;
    } else {
      return fail(QStringLiteral("no command given"));
    }
    out.ok = true;
    return out;
  }

  const QString name = positional.takeFirst();
  const std::optional<Verb> verb = verbFromName(name);
  if(!verb || *verb == Verb::Version) {
    return fail(QStringLiteral("unknown command '%1'").arg(name));
  }
  r.verb = parser.isSet(help) ? Verb::Help : *verb;
  if(r.verb == Verb::Help) {
    out.ok = true;
    return out;
  }

  r.json = parser.isSet(json);
  r.profile = parser.value(profile).trimmed();
  r.status = parser.value(status).trimmed();
  r.format = parser.value(format);

  // Options a command does not use are refused rather than ignored: a typo'd
  // `heap list --stauts done` silently listing everything looks like it worked.
  const auto refuse = [&](const QCommandLineOption& o) -> bool {
    return parser.isSet(o);
  };
  const auto notFor = [&](const QString& option) {
    return fail(QStringLiteral("--%1 is not an option of '%2'").arg(option, name));
  };
  if(refuse(version)) {
    return notFor(QStringLiteral("version"));
  }

  switch(r.verb) {
    case Verb::Add:
      if(refuse(status)) {
        return notFor(QStringLiteral("status"));
      }
      if(refuse(format)) {
        return notFor(QStringLiteral("format"));
      }
      r.text = positional.join(QChar(' ')).trimmed();
      if(r.text.isEmpty()) {
        return fail(QStringLiteral("add needs the text of the task, e.g. heap add \"fix login tomorrow p1\""));
      }
      break;
    case Verb::Now:
      if(refuse(status)) {
        return notFor(QStringLiteral("status"));
      }
      if(refuse(profile)) {
        return notFor(QStringLiteral("profile"));
      }
      if(!positional.isEmpty()) {
        return fail(QStringLiteral("unexpected argument '%1'").arg(positional.constFirst()));
      }
      break;
    case Verb::List:
    case Verb::Today:
      if(refuse(format)) {
        return notFor(QStringLiteral("format"));
      }
      if(r.verb == Verb::Today && refuse(status)) {
        return notFor(QStringLiteral("status"));
      }
      if(!positional.isEmpty()) {
        return fail(QStringLiteral("unexpected argument '%1'").arg(positional.constFirst()));
      }
      break;
    case Verb::Done:
    case Verb::Open:
      if(refuse(status)) {
        return notFor(QStringLiteral("status"));
      }
      if(refuse(format)) {
        return notFor(QStringLiteral("format"));
      }
      if(positional.size() != 1 || positional.constFirst().trimmed().isEmpty()) {
        return fail(positional.isEmpty() ? QStringLiteral("%1 needs a task id, e.g. heap %1 APP-12").arg(name)
                                         : QStringLiteral("unexpected argument '%1'").arg(positional.at(1)));
      }
      r.taskId = positional.constFirst().trimmed();
      break;
    case Verb::Help:
    case Verb::Version:
      break;
  }
  out.ok = true;
  return out;
}

// ── Wire format ────────────────────────────────────────────────────────────

QByteArray encodeRequest(const Request& r) {
  QJsonObject o;
  o.insert(QStringLiteral("heap"), 1);
  o.insert(QStringLiteral("verb"), verbName(r.verb));
  const auto put = [&o](const char* key, const QString& value) {
    if(!value.isEmpty()) {
      o.insert(QLatin1String(key), value);
    }
  };
  put("text", r.text);
  put("id", r.taskId);
  put("profile", r.profile);
  put("status", r.status);
  put("format", r.format);
  put("branch", r.branch);
  if(r.json) {
    o.insert(QStringLiteral("json"), true);
  }
  // Compact JSON escapes control characters, so the request is one line.
  return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

std::optional<Request> decodeRequest(const QByteArray& line) {
  const QJsonDocument doc = QJsonDocument::fromJson(line.trimmed());
  if(!doc.isObject()) {
    return std::nullopt;
  }
  const QJsonObject o = doc.object();
  if(o.value(QStringLiteral("heap")).toInt() != 1) {
    return std::nullopt;
  }
  const std::optional<Verb> verb = verbFromName(o.value(QStringLiteral("verb")).toString());
  if(!verb) {
    return std::nullopt;
  }
  Request r;
  r.verb = *verb;
  r.text = o.value(QStringLiteral("text")).toString();
  r.taskId = o.value(QStringLiteral("id")).toString();
  r.profile = o.value(QStringLiteral("profile")).toString();
  r.status = o.value(QStringLiteral("status")).toString();
  r.format = o.value(QStringLiteral("format")).toString();
  r.branch = o.value(QStringLiteral("branch")).toString();
  r.json = o.value(QStringLiteral("json")).toBool();
  return r;
}

QByteArray encodeResponse(const Response& r) {
  QJsonObject o;
  o.insert(QStringLiteral("exit"), r.exitCode);
  o.insert(QStringLiteral("out"), r.out);
  o.insert(QStringLiteral("err"), r.err);
  return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

std::optional<Response> decodeResponse(const QByteArray& line) {
  const QJsonDocument doc = QJsonDocument::fromJson(line.trimmed());
  if(!doc.isObject() || !doc.object().value(QStringLiteral("exit")).isDouble()) {
    return std::nullopt;
  }
  const QJsonObject o = doc.object();
  Response r;
  r.exitCode = o.value(QStringLiteral("exit")).toInt();
  r.out = o.value(QStringLiteral("out")).toString();
  r.err = o.value(QStringLiteral("err")).toString();
  return r;
}

// ── Snapshot ───────────────────────────────────────────────────────────────

Snapshot snapshotFromProfiles(const QVector<Profile>& profiles, const QString& activeProfileId, const QString& idPrefix) {
  Snapshot s;
  s.activeProfileId = activeProfileId;
  s.idPrefix = idPrefix;
  s.profiles.reserve(profiles.size());
  for(const Profile& p : profiles) {
    s.profiles.append({p.id, p.name, p.tasks, p.statuses});
  }
  return s;
}

std::optional<Snapshot> snapshotFromState(QJsonObject root, QString* error) {
  const int schema = root.value(QStringLiteral("schemaVersion")).toInt(1);
  if(schema < 2 || !root.value(QStringLiteral("profiles")).isArray()) {
    if(error != nullptr) {
      *error = QStringLiteral("state.json has no profiles (an old format): open heap once to upgrade it");
    }
    return std::nullopt;
  }
  if(schema < heap::state::kSchemaVersion) {
    heap::state::migrateState(root, schema);  // in memory only
  }
  Snapshot s;
  const QJsonArray profiles = root.value(QStringLiteral("profiles")).toArray();
  for(const QJsonValueConstRef v : profiles) {
    if(!v.isObject()) {
      continue;
    }
    const Profile p = heap::state::profileFromJson(v.toObject());
    s.profiles.append({p.id, p.name, p.tasks, p.statuses});
  }
  s.activeProfileId = root.value(QStringLiteral("activeProfileId")).toString();
  const bool activeExists = std::any_of(s.profiles.cbegin(), s.profiles.cend(), [&s](const ProfileData& p) {
    return p.id == s.activeProfileId;
  });
  if(!activeExists && !s.profiles.isEmpty()) {
    s.activeProfileId = s.profiles.constFirst().id;
  }
  const QString prefix = root.value(QStringLiteral("settings"))
                             .toObject()
                             .value(QStringLiteral("app"))
                             .toObject()
                             .value(QStringLiteral("tasks"))
                             .toObject()
                             .value(QStringLiteral("idPrefix"))
                             .toString(QStringLiteral("TASK"));
  s.idPrefix = prefix.trimmed().toUpper();
  return s;
}

// ── Questions ──────────────────────────────────────────────────────────────

int findProfile(const Snapshot& s, const QString& wanted) {
  const QString key = wanted.trimmed();
  if(key.isEmpty()) {
    for(qsizetype i = 0; i < s.profiles.size(); ++i) {
      if(s.profiles.at(i).id == s.activeProfileId) {
        return static_cast<int>(i);
      }
    }
    return s.profiles.isEmpty() ? -1 : 0;
  }
  for(qsizetype i = 0; i < s.profiles.size(); ++i) {
    if(s.profiles.at(i).id == key) {
      return static_cast<int>(i);
    }
  }
  for(qsizetype i = 0; i < s.profiles.size(); ++i) {
    const ProfileData& p = s.profiles.at(i);
    if(p.name.trimmed().compare(key, Qt::CaseInsensitive) == 0 || p.id.compare(key, Qt::CaseInsensitive) == 0) {
      return static_cast<int>(i);
    }
  }
  return -1;
}

TaskRef findTask(const Snapshot& s, const QString& query, int preferred) {
  const QString q = query.trimmed();
  if(q.isEmpty()) {
    return {};
  }
  QVector<int> order;
  if(preferred >= 0 && preferred < s.profiles.size()) {
    order << preferred;
  }
  for(int i = 0; i < s.profiles.size(); ++i) {
    if(i != preferred) {
      order << i;
    }
  }
  // Exact id beats any-case id beats tracker key, across all profiles: a
  // precise answer elsewhere is better than a loose one here.
  const auto search = [&](const auto& matches) -> TaskRef {
    for(const int pi : order) {
      const QVector<Task>& tasks = s.profiles.at(pi).tasks;
      for(qsizetype ti = 0; ti < tasks.size(); ++ti) {
        if(matches(tasks.at(ti))) {
          return {pi, static_cast<int>(ti)};
        }
      }
    }
    return {};
  };
  TaskRef hit = search([&q](const Task& t) {
    return t.id == q;
  });
  if(!hit.found()) {
    hit = search([&q](const Task& t) {
      return t.id.compare(q, Qt::CaseInsensitive) == 0;
    });
  }
  if(!hit.found()) {
    hit = search([&q](const Task& t) {
      return !t.externalId.isEmpty() && externalKeyOf(t).compare(q, Qt::CaseInsensitive) == 0;
    });
  }
  return hit;
}

NowResult resolveNow(const Snapshot& s, const QString& branch) {
  const int active = findProfile(s, QString());
  QVector<int> order;
  if(active >= 0) {
    order << active;
  }
  for(int i = 0; i < s.profiles.size(); ++i) {
    if(i != active) {
      order << i;
    }
  }
  // 1. A running timer says it outright.
  for(const int pi : order) {
    const QVector<Task>& tasks = s.profiles.at(pi).tasks;
    int best = -1;
    for(qsizetype ti = 0; ti < tasks.size(); ++ti) {
      const Task& t = tasks.at(ti);
      if(t.archived || !t.timerStartedAt.isValid()) {
        continue;
      }
      if(best < 0 || t.timerStartedAt > tasks.at(best).timerStartedAt) {
        best = static_cast<int>(ti);
      }
    }
    if(best >= 0) {
      return {{pi, best}, QStringLiteral("timer")};
    }
  }
  // 2. The branch checked out where the command runs, as the git banner reads it.
  if(active >= 0 && !branch.isEmpty()) {
    const ProfileData& p = s.profiles.at(active);
    const QString id = heap::git::taskIdForBranch(branch, s.idPrefix, p.tasks);
    for(qsizetype ti = 0; ti < p.tasks.size() && !id.isEmpty(); ++ti) {
      if(p.tasks.at(ti).id == id && !p.tasks.at(ti).archived) {
        return {{active, static_cast<int>(ti)}, QStringLiteral("branch")};
      }
    }
  }
  return {};
}

QString statusName(const QVariantList& statuses, const QString& statusId) {
  for(const QVariant& v : statuses) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("id")).toString() == statusId) {
      const QString name = m.value(QStringLiteral("name")).toString();
      return name.isEmpty() ? statusId : name;
    }
  }
  return statusId;
}

bool isDoingStatus(const QVariantList& statuses, const QString& statusId) {
  if(statusId == QLatin1String("prog")) {
    return true;
  }
  for(const QVariant& v : statuses) {
    const QVariantMap m = v.toMap();
    if(m.value(QStringLiteral("id")).toString() == statusId) {
      return m.value(QStringLiteral("doing")).toBool();
    }
  }
  return false;
}

QString findStatus(const QVariantList& statuses, const QString& wanted) {
  const QString key = wanted.trimmed();
  for(const QVariant& v : statuses) {
    const QString id = v.toMap().value(QStringLiteral("id")).toString();
    if(id == key) {
      return id;
    }
  }
  for(const QVariant& v : statuses) {
    const QVariantMap m = v.toMap();
    const QString id = m.value(QStringLiteral("id")).toString();
    if(id.compare(key, Qt::CaseInsensitive) == 0 ||
       m.value(QStringLiteral("name")).toString().trimmed().compare(key, Qt::CaseInsensitive) == 0) {
      return id;
    }
  }
  return {};
}

QString doneStatus(const QVariantList& statuses) {
  if(!findStatus(statuses, QStringLiteral("done")).isEmpty() || statuses.isEmpty()) {
    return QStringLiteral("done");
  }
  return statuses.constLast().toMap().value(QStringLiteral("id")).toString();
}

namespace {

qsizetype columnIndex(const QVariantList& statuses, const QString& statusId) {
  for(qsizetype i = 0; i < statuses.size(); ++i) {
    if(statuses.at(i).toMap().value(QStringLiteral("id")).toString() == statusId) {
      return i;
    }
  }
  return statuses.size();  // an unknown column sorts last
}

void sortBoardOrder(const ProfileData& p, QVector<int>& rows) {
  std::stable_sort(rows.begin(), rows.end(), [&p](int a, int b) {
    const Task& ta = p.tasks.at(a);
    const Task& tb = p.tasks.at(b);
    const qsizetype ca = columnIndex(p.statuses, ta.status);
    const qsizetype cb = columnIndex(p.statuses, tb.status);
    if(ca != cb) {
      return ca < cb;
    }
    return ta.rank < tb.rank;
  });
}

QString isoOrEmpty(const QDateTime& dt, bool hasTime) {
  if(!dt.isValid()) {
    return {};
  }
  return hasTime ? dt.toString(Qt::ISODate) : dt.date().toString(Qt::ISODate);
}

QString humanWhen(const QDateTime& dt, bool hasTime) {
  if(!dt.isValid()) {
    return {};
  }
  return hasTime ? dt.toString(QStringLiteral("yyyy-MM-dd HH:mm")) : dt.date().toString(Qt::ISODate);
}

qint64 trackedSecondsAt(const Task& t, const QDateTime& now) {
  qint64 secs = t.trackedSeconds;
  if(t.timerStartedAt.isValid() && now.isValid()) {
    secs += std::max<qint64>(0, t.timerStartedAt.secsTo(now));
  }
  return secs;
}

QString humanDuration(qint64 secs) {
  const qint64 minutes = secs / 60;
  if(minutes < 60) {
    return QStringLiteral("%1m").arg(minutes);
  }
  return QStringLiteral("%1h %2m").arg(minutes / 60).arg(minutes % 60, 2, 10, QChar('0'));
}

}  // namespace

QVector<int> listTasks(const ProfileData& p, const QString& statusId) {
  QVector<int> rows;
  for(qsizetype i = 0; i < p.tasks.size(); ++i) {
    const Task& t = p.tasks.at(i);
    if(t.archived || (!statusId.isEmpty() && t.status != statusId)) {
      continue;
    }
    rows << static_cast<int>(i);
  }
  sortBoardOrder(p, rows);
  return rows;
}

QVector<int> todayTasks(const ProfileData& p, const QDate& today) {
  const QString done = doneStatus(p.statuses);
  QVector<int> rows;
  for(qsizetype i = 0; i < p.tasks.size(); ++i) {
    const Task& t = p.tasks.at(i);
    if(t.archived || t.status == done || t.status == QLatin1String("done")) {
      continue;
    }
    const bool doing = isDoingStatus(p.statuses, t.status);
    const bool planned =
        !t.someday && ((t.scheduledAt.isValid() && t.scheduledAt.date() == today) || (t.dueAt.isValid() && t.dueAt.date() == today));
    if(doing || planned) {
      rows << static_cast<int>(i);
    }
  }
  sortBoardOrder(p, rows);
  return rows;
}

// ── Output ─────────────────────────────────────────────────────────────────

QJsonObject taskJson(const ProfileData& p, const Task& t, const QDateTime& now) {
  QJsonObject o;
  o.insert(QStringLiteral("id"), t.id);
  o.insert(QStringLiteral("title"), t.title);
  o.insert(QStringLiteral("status"), t.status);
  o.insert(QStringLiteral("statusName"), statusName(p.statuses, t.status));
  o.insert(QStringLiteral("priority"), t.priority);
  o.insert(QStringLiteral("profile"), p.id);
  o.insert(QStringLiteral("profileName"), p.name);
  const QString scheduled = isoOrEmpty(t.scheduledAt, t.scheduledHasTime);
  const QString due = isoOrEmpty(t.dueAt, t.dueHasTime);
  o.insert(QStringLiteral("scheduledAt"), scheduled.isEmpty() ? QJsonValue() : QJsonValue(scheduled));
  o.insert(QStringLiteral("dueAt"), due.isEmpty() ? QJsonValue() : QJsonValue(due));
  QJsonArray labels;
  for(const Label& l : t.labels) {
    labels.append(l.id);
  }
  o.insert(QStringLiteral("labels"), labels);
  if(!t.desc.isEmpty()) {
    o.insert(QStringLiteral("desc"), t.desc);
  }
  if(!t.branch.isEmpty()) {
    o.insert(QStringLiteral("branch"), t.branch);
  }
  if(!t.externalUrl.isEmpty()) {
    o.insert(QStringLiteral("url"), t.externalUrl);
  }
  o.insert(QStringLiteral("trackedSeconds"), static_cast<double>(trackedSecondsAt(t, now)));
  o.insert(QStringLiteral("timerRunning"), t.timerStartedAt.isValid());
  return o;
}

QString taskLines(const ProfileData& p, const QVector<int>& rows) {
  qsizetype idWidth = 0;
  qsizetype statusWidth = 0;
  for(const int r : rows) {
    idWidth = std::max(idWidth, p.tasks.at(r).id.size());
    statusWidth = std::max(statusWidth, statusName(p.statuses, p.tasks.at(r).status).size() + 2);
  }
  QString out;
  for(const int r : rows) {
    const Task& t = p.tasks.at(r);
    QString line = t.id.leftJustified(idWidth) + QStringLiteral("  ") +
                   (QChar('[') + statusName(p.statuses, t.status) + QChar(']')).leftJustified(statusWidth) + QStringLiteral("  ") +
                   t.priority.leftJustified(2) + QStringLiteral("  ") + t.title;
    if(t.dueAt.isValid()) {
      line += QStringLiteral("  (due %1)").arg(humanWhen(t.dueAt, t.dueHasTime));
    } else if(t.scheduledAt.isValid()) {
      line += QStringLiteral("  (%1)").arg(humanWhen(t.scheduledAt, t.scheduledHasTime));
    }
    out += line + QChar('\n');
  }
  return out;
}

QString formatNow(const QString& format, const ProfileData& p, const Task& t, const QString& source, const QDateTime& now) {
  const QString out = format.isEmpty() ? QStringLiteral("{id} {title}") : format;
  // One pass, left to right, so a title containing "{id}" stays as typed.
  const QVector<QPair<QString, QString>> fields = {
      {QStringLiteral("{id}"), t.id},
      {QStringLiteral("{title}"), t.title},
      {QStringLiteral("{status}"), statusName(p.statuses, t.status)},
      {QStringLiteral("{priority}"), t.priority},
      {QStringLiteral("{profile}"), p.name.isEmpty() ? p.id : p.name},
      {QStringLiteral("{source}"), source},
      {QStringLiteral("{elapsed}"), humanDuration(trackedSecondsAt(t, now))},
  };
  QString result;
  qsizetype i = 0;
  while(i < out.size()) {
    bool replaced = false;
    if(out.at(i) == QChar('{')) {
      for(const auto& [key, value] : fields) {
        if(QStringView(out).mid(i).startsWith(key)) {
          result += value;
          i += key.size();
          replaced = true;
          break;
        }
      }
    }
    if(!replaced) {
      result += out.at(i);
      ++i;
    }
  }
  // Escapes a prompt string may want.
  result.replace(QStringLiteral("\\n"), QStringLiteral("\n")).replace(QStringLiteral("\\t"), QStringLiteral("\t"));
  return result;
}

Response answer(const Snapshot& s, const Request& r, const QDateTime& now) {
  Response resp;
  const auto jsonText = [](const QJsonDocument& doc) {
    return QString::fromUtf8(doc.toJson(QJsonDocument::Indented));
  };

  if(r.verb == Verb::Now) {
    const NowResult hit = resolveNow(s, r.branch);
    if(!hit.ref.found()) {
      // Nothing current is not an error: a prompt calls this on every line.
      if(r.json) {
        resp.out = QStringLiteral("null\n");
      }
      return resp;
    }
    const ProfileData& p = s.profiles.at(hit.ref.profile);
    const Task& t = p.tasks.at(hit.ref.task);
    if(r.json) {
      QJsonObject o = taskJson(p, t, now);
      o.insert(QStringLiteral("source"), hit.source);
      resp.out = jsonText(QJsonDocument(o));
    } else {
      resp.out = formatNow(r.format, p, t, hit.source, now) + QChar('\n');
    }
    return resp;
  }

  if(r.verb == Verb::List || r.verb == Verb::Today) {
    if(s.profiles.isEmpty()) {
      resp.out = r.json ? QStringLiteral("[]\n") : QString();
      return resp;
    }
    const int pi = findProfile(s, r.profile);
    if(pi < 0) {
      resp.exitCode = kExitNotFound;
      resp.err = QStringLiteral("heap: no profile '%1'\n").arg(r.profile);
      return resp;
    }
    const ProfileData& p = s.profiles.at(pi);
    QString statusId;
    if(!r.status.isEmpty()) {
      statusId = findStatus(p.statuses, r.status);
      if(statusId.isEmpty()) {
        resp.exitCode = kExitNotFound;
        resp.err = QStringLiteral("heap: no column '%1' in profile '%2'\n").arg(r.status, p.name);
        return resp;
      }
    }
    const QVector<int> rows = r.verb == Verb::List ? listTasks(p, statusId) : todayTasks(p, now.date());
    if(r.json) {
      QJsonArray arr;
      for(const int row : rows) {
        arr.append(taskJson(p, p.tasks.at(row), now));
      }
      resp.out = jsonText(QJsonDocument(arr));
    } else {
      resp.out = taskLines(p, rows);
    }
    return resp;
  }

  resp.exitCode = kExitUsage;
  resp.err = QStringLiteral("heap: '%1' changes data and cannot be answered from a snapshot\n").arg(verbName(r.verb));
  return resp;
}

QString branchAt(const QString& dir) {
  QDir d(dir.isEmpty() ? QDir::currentPath() : dir);
  // Walk up to the work tree's root, as git does.
  for(int depth = 0; depth < 64; ++depth) {
    const QString gitDir = heap::git::BranchTaskMatcher::resolveGitDir(d.absolutePath());
    if(!gitDir.isEmpty()) {
      QFile head(QDir(gitDir).filePath(QStringLiteral("HEAD")));
      if(!head.open(QIODevice::ReadOnly)) {
        return {};
      }
      const QString branch = heap::git::BranchTaskMatcher::branchFromHeadText(QString::fromUtf8(head.read(4096)));
      return branch == QLatin1String("(detached HEAD)") ? QString() : branch;
    }
    if(!d.cdUp()) {
      break;
    }
  }
  return {};
}

}  // namespace heap::cli
