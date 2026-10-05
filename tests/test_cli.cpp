// The command line (APP-173): verb detection, argument parsing, the wire
// format to a running window, `heap now`'s resolution order and the read-only
// answers — all pure — plus `add` and `done` through a headless AppController
// into a temporary data dir, read back from the state.json it saved.
//
// Runs under a plain QCoreApplication, as `heap add` does: the headless
// controller must not need a GUI application.

#include "AppController.h"
#include "Models.h"
#include "StateSerializer.h"

#include "cli/CliCore.h"
#include "cli/CliExecutor.h"
#include "cli/VerbScan.h"
#include "platform/Paths.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTemporaryDir>

#include <gtest/gtest.h>

#include <string_view>
#include <vector>

using namespace heap::cli;

namespace {

Invocation classifyArgs(std::initializer_list<std::string_view> args) {
  const std::vector<std::string_view> v(args);
  return classify<char>(v);
}

Task mkTask(const QString& id, const QString& title, const QString& status = QStringLiteral("todo")) {
  Task t;
  t.id = id;
  t.title = title;
  t.status = status;
  t.priority = QStringLiteral("P2");
  return t;
}

QVariantList columns() {
  QVariantList out;
  for(const auto& [id, name] : {std::pair{"todo", "To Do"}, {"prog", "In Progress"}, {"review", "Review"}, {"done", "Done"}}) {
    out.append(QVariantMap{{QStringLiteral("id"), QString::fromLatin1(id)}, {QStringLiteral("name"), QString::fromLatin1(name)}});
  }
  return out;
}

Snapshot twoProfiles() {
  Snapshot s;
  s.activeProfileId = QStringLiteral("work");
  s.idPrefix = QStringLiteral("APP");
  s.profiles.append({QStringLiteral("work"), QStringLiteral("Work"), {mkTask("APP-1", "login"), mkTask("APP-2", "search")}, columns()});
  s.profiles.append({QStringLiteral("home"), QStringLiteral("Home"), {mkTask("HOME-1", "taxes")}, columns()});
  return s;
}

QString dataFile() {
  return QDir(heap::paths::dataDir()).filePath(QStringLiteral("state.json"));
}

Snapshot reload() {
  QFile f(dataFile());
  EXPECT_TRUE(f.open(QIODevice::ReadOnly));
  const std::optional<Snapshot> s = snapshotFromState(QJsonDocument::fromJson(f.readAll()).object());
  EXPECT_TRUE(s.has_value());
  return s.value_or(Snapshot{});
}

}  // namespace

// ── Verb detection (before any Qt object exists) ──────────────────────────

TEST(CliVerbScan, FirstPositionalDecides) {
  EXPECT_EQ(classifyArgs({"add", "fix login"}), Invocation::Command);
  EXPECT_EQ(classifyArgs({"now"}), Invocation::Command);
  EXPECT_EQ(classifyArgs({"--data-dir", "C:/x", "list"}), Invocation::Command);
  EXPECT_EQ(classifyArgs({"--json", "today"}), Invocation::Command);
  EXPECT_EQ(classifyArgs({"--help"}), Invocation::Command);
  EXPECT_EQ(classifyArgs({"-v"}), Invocation::Command);
}

TEST(CliVerbScan, WindowLaunchesStayWindowLaunches) {
  EXPECT_EQ(classifyArgs({}), Invocation::Window);
  EXPECT_EQ(classifyArgs({"--view", "board"}), Invocation::Window);
  EXPECT_EQ(classifyArgs({"board"}), Invocation::Window);  // refused later, as before
  // An option's value is never the verb: a data dir called "add".
  EXPECT_EQ(classifyArgs({"--data-dir", "add"}), Invocation::Window);
  EXPECT_EQ(classifyArgs({"-platform", "now"}), Invocation::Window);
  EXPECT_EQ(classifyArgs({"--", "add"}), Invocation::Window);
  EXPECT_EQ(classifyArgs({"--smoke"}), Invocation::Window);
}

// ── Arguments ─────────────────────────────────────────────────────────────

TEST(CliArgs, AddJoinsTheWordsOfTheText) {
  const ParsedArgs p =
      parseArgs({QStringLiteral("add"), QStringLiteral("fix"), QStringLiteral("login tomorrow"), QStringLiteral("--json")});
  ASSERT_TRUE(p.ok) << qPrintable(p.error);
  EXPECT_EQ(p.request.verb, Verb::Add);
  EXPECT_EQ(p.request.text, QStringLiteral("fix login tomorrow"));
  EXPECT_TRUE(p.request.json);
}

TEST(CliArgs, OptionsAnywhereAndDataDir) {
  const ParsedArgs p = parseArgs({QStringLiteral("--data-dir"),
                                  QStringLiteral("D:/p"),
                                  QStringLiteral("list"),
                                  QStringLiteral("--status"),
                                  QStringLiteral("In Progress"),
                                  QStringLiteral("--profile"),
                                  QStringLiteral("Work")});
  ASSERT_TRUE(p.ok) << qPrintable(p.error);
  EXPECT_EQ(p.request.verb, Verb::List);
  EXPECT_EQ(p.request.status, QStringLiteral("In Progress"));
  EXPECT_EQ(p.request.profile, QStringLiteral("Work"));
  EXPECT_TRUE(p.dataDirSet);
  EXPECT_EQ(p.dataDir, QStringLiteral("D:/p"));
}

TEST(CliArgs, NowTakesFormat) {
  const ParsedArgs p = parseArgs({QStringLiteral("now"), QStringLiteral("--format"), QStringLiteral("{id}")});
  ASSERT_TRUE(p.ok);
  EXPECT_EQ(p.request.verb, Verb::Now);
  EXPECT_EQ(p.request.format, QStringLiteral("{id}"));
}

TEST(CliArgs, DoneAndOpenTakeExactlyOneId) {
  const ParsedArgs p = parseArgs({QStringLiteral("done"), QStringLiteral("APP-12")});
  ASSERT_TRUE(p.ok);
  EXPECT_EQ(p.request.verb, Verb::Done);
  EXPECT_EQ(p.request.taskId, QStringLiteral("APP-12"));
  EXPECT_FALSE(parseArgs({QStringLiteral("done")}).ok);
  EXPECT_FALSE(parseArgs({QStringLiteral("open"), QStringLiteral("A-1"), QStringLiteral("A-2")}).ok);
}

TEST(CliArgs, RefusesWhatACommandDoesNotUse) {
  EXPECT_FALSE(parseArgs({QStringLiteral("add")}).ok);  // no text
  EXPECT_FALSE(parseArgs({QStringLiteral("now"), QStringLiteral("--status"), QStringLiteral("x")}).ok);
  EXPECT_FALSE(parseArgs({QStringLiteral("now"), QStringLiteral("extra")}).ok);
  EXPECT_FALSE(parseArgs({QStringLiteral("today"), QStringLiteral("--status"), QStringLiteral("x")}).ok);
  EXPECT_FALSE(parseArgs({QStringLiteral("list"), QStringLiteral("--stauts"), QStringLiteral("x")}).ok);
  EXPECT_FALSE(parseArgs({QStringLiteral("frobnicate")}).ok);
  EXPECT_FALSE(parseArgs({QStringLiteral("list"), QStringLiteral("--data-dir"), QString()}).ok);
}

TEST(CliArgs, HelpAndVersion) {
  EXPECT_EQ(parseArgs({QStringLiteral("help")}).request.verb, Verb::Help);
  EXPECT_EQ(parseArgs({QStringLiteral("--help")}).request.verb, Verb::Help);
  EXPECT_EQ(parseArgs({QStringLiteral("add"), QStringLiteral("--help")}).request.verb, Verb::Help);
  EXPECT_EQ(parseArgs({QStringLiteral("--version")}).request.verb, Verb::Version);
  EXPECT_TRUE(helpText().contains(QStringLiteral("now [--json]")));
}

// ── Wire format ───────────────────────────────────────────────────────────

TEST(CliIpc, RequestRoundTripsOnOneLine) {
  Request r;
  r.verb = Verb::Add;
  r.text = QStringLiteral("отчёт\nв пятницу \"p1\"");
  r.profile = QStringLiteral("Work");
  r.json = true;
  r.branch = QStringLiteral("feature/APP-1-x");
  const QByteArray line = encodeRequest(r);
  EXPECT_FALSE(line.contains('\n'));
  EXPECT_TRUE(line.startsWith('{'));
  const std::optional<Request> back = decodeRequest(line);
  ASSERT_TRUE(back.has_value());
  const Request b = back.value_or(Request{});
  EXPECT_EQ(b.verb, Verb::Add);
  EXPECT_EQ(b.text, r.text);
  EXPECT_EQ(b.profile, r.profile);
  EXPECT_EQ(b.branch, r.branch);
  EXPECT_TRUE(b.json);
}

TEST(CliIpc, ResponseRoundTrips) {
  const Response r{kExitNotFound, QStringLiteral("a\nb\n"), QStringLiteral("heap: no task 'X'\n")};
  const QByteArray line = encodeResponse(r);
  EXPECT_FALSE(line.contains('\n'));
  const std::optional<Response> back = decodeResponse(line);
  ASSERT_TRUE(back.has_value());
  const Response b = back.value_or(Response{});
  EXPECT_EQ(b.exitCode, kExitNotFound);
  EXPECT_EQ(b.out, r.out);
  EXPECT_EQ(b.err, r.err);
}

TEST(CliIpc, OlderMessagesAreNotRequests) {
  EXPECT_FALSE(decodeRequest("activate view=board").has_value());
  EXPECT_FALSE(decodeRequest("{\"verb\":\"add\"}").has_value());  // no protocol version
  EXPECT_FALSE(decodeRequest("{\"heap\":1,\"verb\":\"rm\"}").has_value());
  EXPECT_FALSE(decodeResponse("ok").has_value());  // a pre-APP-173 window
}

// ── `heap now` ────────────────────────────────────────────────────────────

TEST(CliNow, NothingCurrentIsNothing) {
  const NowResult r = resolveNow(twoProfiles(), QString());
  EXPECT_FALSE(r.ref.found());
  EXPECT_TRUE(r.source.isEmpty());
}

TEST(CliNow, BranchNamesTheTask) {
  const Snapshot s = twoProfiles();
  const NowResult r = resolveNow(s, QStringLiteral("feature/APP-2-search"));
  ASSERT_TRUE(r.ref.found());
  EXPECT_EQ(s.profiles.at(r.ref.profile).tasks.at(r.ref.task).id, QStringLiteral("APP-2"));
  EXPECT_EQ(r.source, QStringLiteral("branch"));
  EXPECT_FALSE(resolveNow(s, QStringLiteral("feature/APP-99-gone")).ref.found());
  EXPECT_FALSE(resolveNow(s, QStringLiteral("main")).ref.found());
}

TEST(CliNow, RunningTimerBeatsTheBranch) {
  Snapshot s = twoProfiles();
  s.profiles[0].tasks[0].timerStartedAt = QDateTime(QDate(2026, 10, 6), QTime(9, 0));
  const NowResult r = resolveNow(s, QStringLiteral("feature/APP-2-search"));
  ASSERT_TRUE(r.ref.found());
  EXPECT_EQ(s.profiles.at(r.ref.profile).tasks.at(r.ref.task).id, QStringLiteral("APP-1"));
  EXPECT_EQ(r.source, QStringLiteral("timer"));
}

TEST(CliNow, LatestTimerWinsAndArchivedNeverCounts) {
  Snapshot s = twoProfiles();
  s.profiles[0].tasks[0].timerStartedAt = QDateTime(QDate(2026, 10, 6), QTime(9, 0));
  s.profiles[0].tasks[1].timerStartedAt = QDateTime(QDate(2026, 10, 6), QTime(10, 0));
  NowResult r = resolveNow(s, QString());
  EXPECT_EQ(s.profiles.at(r.ref.profile).tasks.at(r.ref.task).id, QStringLiteral("APP-2"));
  s.profiles[0].tasks[1].archived = true;
  r = resolveNow(s, QString());
  EXPECT_EQ(s.profiles.at(r.ref.profile).tasks.at(r.ref.task).id, QStringLiteral("APP-1"));
}

TEST(CliNow, TimerInAnotherProfileStillCounts) {
  Snapshot s = twoProfiles();
  s.profiles[1].tasks[0].timerStartedAt = QDateTime(QDate(2026, 10, 6), QTime(9, 0));
  const NowResult r = resolveNow(s, QStringLiteral("feature/APP-2-search"));
  ASSERT_TRUE(r.ref.found());
  EXPECT_EQ(r.ref.profile, 1);
  EXPECT_EQ(r.source, QStringLiteral("timer"));
}

TEST(CliNow, BranchResolvesAMirroredIssueByItsKey) {
  Snapshot s = twoProfiles();
  Task issue = mkTask(QStringLiteral("jira-LUX-7"), QStringLiteral("mirrored"));
  issue.externalId = QStringLiteral("LUX-7");
  issue.externalProvider = QStringLiteral("jira");
  s.profiles[0].tasks.append(issue);
  const NowResult r = resolveNow(s, QStringLiteral("LUX-7-fix"));
  ASSERT_TRUE(r.ref.found());
  EXPECT_EQ(s.profiles.at(r.ref.profile).tasks.at(r.ref.task).id, QStringLiteral("jira-LUX-7"));
}

TEST(CliNow, FormatFields) {
  const Snapshot s = twoProfiles();
  Task t = s.profiles.at(0).tasks.at(0);
  t.trackedSeconds = 3600;
  t.timerStartedAt = QDateTime(QDate(2026, 10, 6), QTime(9, 0));
  const QDateTime now(QDate(2026, 10, 6), QTime(9, 5));
  EXPECT_EQ(formatNow(QString(), s.profiles.at(0), t, QStringLiteral("timer"), now), QStringLiteral("APP-1 login"));
  EXPECT_EQ(
      formatNow(
          QStringLiteral("[{id}|{status}|{priority}|{profile}|{source}|{elapsed}]"), s.profiles.at(0), t, QStringLiteral("timer"), now),
      QStringLiteral("[APP-1|To Do|P2|Work|timer|1h 05m]"));
  t.title = QStringLiteral("literal {id}");
  EXPECT_EQ(formatNow(QStringLiteral("{title}"), s.profiles.at(0), t, QString(), now), QStringLiteral("literal {id}"));
}

// ── list / today / lookup ─────────────────────────────────────────────────

TEST(CliQueries, ListIsBoardOrderWithoutArchived) {
  ProfileData p{QStringLiteral("w"), QStringLiteral("W"), {}, columns()};
  p.tasks = {
      mkTask("A-1", "done one", "done"), mkTask("A-2", "second", "todo"), mkTask("A-3", "first", "todo"), mkTask("A-4", "old", "todo")};
  p.tasks[1].rank = 2048;
  p.tasks[2].rank = 1024;
  p.tasks[3].archived = true;
  const QVector<int> rows = listTasks(p, QString());
  ASSERT_EQ(rows.size(), 3);
  EXPECT_EQ(p.tasks.at(rows[0]).id, QStringLiteral("A-3"));
  EXPECT_EQ(p.tasks.at(rows[1]).id, QStringLiteral("A-2"));
  EXPECT_EQ(p.tasks.at(rows[2]).id, QStringLiteral("A-1"));
  EXPECT_EQ(listTasks(p, QStringLiteral("done")).size(), 1);
  EXPECT_EQ(findStatus(p.statuses, QStringLiteral("in progress")), QStringLiteral("prog"));
}

TEST(CliQueries, TodayIsDoingOrScheduledOrDueToday) {
  const QDate today(2026, 10, 6);
  ProfileData p{QStringLiteral("w"), QStringLiteral("W"), {}, columns()};
  p.tasks = {mkTask("T-1", "doing", "prog"),
             mkTask("T-2", "due today", "todo"),
             mkTask("T-3", "tomorrow", "todo"),
             mkTask("T-4", "done today", "done"),
             mkTask("T-5", "someday", "todo"),
             mkTask("T-6", "scheduled", "review")};
  p.tasks[1].dueAt = QDateTime(today, QTime(17, 0));
  p.tasks[2].dueAt = QDateTime(today.addDays(1), QTime(0, 0));
  p.tasks[3].dueAt = QDateTime(today, QTime(0, 0));
  p.tasks[4].dueAt = QDateTime(today, QTime(0, 0));
  p.tasks[4].someday = true;
  p.tasks[5].scheduledAt = QDateTime(today, QTime(14, 0));
  QStringList ids;
  for(const int r : todayTasks(p, today)) {
    ids << p.tasks.at(r).id;
  }
  EXPECT_EQ(ids, (QStringList{QStringLiteral("T-2"), QStringLiteral("T-1"), QStringLiteral("T-6")}));
}

TEST(CliQueries, FindTaskPrefersExactThenAnyCaseThenKey) {
  const Snapshot s = twoProfiles();
  EXPECT_EQ(findTask(s, QStringLiteral("app-1"), 0).task, 0);
  const TaskRef home = findTask(s, QStringLiteral("HOME-1"), 0);
  EXPECT_EQ(home.profile, 1);
  EXPECT_FALSE(findTask(s, QStringLiteral("NOPE-1"), 0).found());
  EXPECT_EQ(findProfile(s, QStringLiteral("home")), 1);
  EXPECT_EQ(findProfile(s, QString()), 0);
  EXPECT_EQ(findProfile(s, QStringLiteral("nope")), -1);
}

TEST(CliQueries, AnswerReportsMissingThingsAsNotFound) {
  const Snapshot s = twoProfiles();
  Request r;
  r.verb = Verb::List;
  r.profile = QStringLiteral("nope");
  EXPECT_EQ(answer(s, r, QDateTime::currentDateTime()).exitCode, kExitNotFound);
  r.profile.clear();
  r.status = QStringLiteral("nope");
  EXPECT_EQ(answer(s, r, QDateTime::currentDateTime()).exitCode, kExitNotFound);
  r.status.clear();
  r.json = true;
  const Response ok = answer(s, r, QDateTime::currentDateTime());
  EXPECT_EQ(ok.exitCode, kExitOk);
  EXPECT_EQ(QJsonDocument::fromJson(ok.out.toUtf8()).array().size(), 2);
  Request now;
  now.verb = Verb::Now;
  EXPECT_EQ(answer(s, now, QDateTime::currentDateTime()).out, QString());  // silent for a prompt
}

TEST(CliSnapshot, ReadsProfilesActiveAndPrefix) {
  Profile a;
  a.id = QStringLiteral("a");
  a.name = QStringLiteral("A");
  a.tasks = {mkTask(QStringLiteral("X-1"), QStringLiteral("one"))};
  QJsonObject root;
  root.insert(QStringLiteral("schemaVersion"), heap::state::kSchemaVersion);
  root.insert(QStringLiteral("profiles"), QJsonArray{heap::state::profileToJson(a)});
  root.insert(QStringLiteral("activeProfileId"), QStringLiteral("gone"));
  root.insert(QStringLiteral("settings"),
              QJsonObject{{QStringLiteral("app"),
                           QJsonObject{{QStringLiteral("tasks"), QJsonObject{{QStringLiteral("idPrefix"), QStringLiteral("x")}}}}}});
  const std::optional<Snapshot> s = snapshotFromState(root);
  ASSERT_TRUE(s.has_value());
  const Snapshot snap = s.value_or(Snapshot{});
  EXPECT_EQ(snap.activeProfileId, QStringLiteral("a"));  // a dangling id falls back to the first
  EXPECT_EQ(snap.idPrefix, QStringLiteral("X"));
  ASSERT_EQ(snap.profiles.size(), 1);
  EXPECT_EQ(snap.profiles.at(0).tasks.at(0).id, QStringLiteral("X-1"));

  QString error;
  EXPECT_FALSE(snapshotFromState(QJsonObject{{QStringLiteral("tasks"), QJsonArray{}}}, &error).has_value());
  EXPECT_FALSE(error.isEmpty());
}

TEST(CliBranch, ReadsHeadOfTheEnclosingWorkTree) {
  const QTemporaryDir dir;
  ASSERT_TRUE(dir.isValid());
  const QDir root(dir.path());
  ASSERT_TRUE(root.mkpath(QStringLiteral("repo/.git")));
  ASSERT_TRUE(root.mkpath(QStringLiteral("repo/src/deep")));
  QFile head(root.filePath(QStringLiteral("repo/.git/HEAD")));
  ASSERT_TRUE(head.open(QIODevice::WriteOnly));
  head.write("ref: refs/heads/feature/APP-2-search\n");
  head.close();
  EXPECT_EQ(branchAt(root.filePath(QStringLiteral("repo/src/deep"))), QStringLiteral("feature/APP-2-search"));

  // A linked worktree: .git is a file naming the private git dir.
  ASSERT_TRUE(root.mkpath(QStringLiteral("repo/.git/worktrees/wt")));
  ASSERT_TRUE(root.mkpath(QStringLiteral("wt")));
  QFile wtHead(root.filePath(QStringLiteral("repo/.git/worktrees/wt/HEAD")));
  ASSERT_TRUE(wtHead.open(QIODevice::WriteOnly));
  wtHead.write("ref: refs/heads/APP-1-login\n");
  wtHead.close();
  QFile link(root.filePath(QStringLiteral("wt/.git")));
  ASSERT_TRUE(link.open(QIODevice::WriteOnly));
  link.write("gitdir: " + root.filePath(QStringLiteral("repo/.git/worktrees/wt")).toUtf8() + "\n");
  link.close();
  EXPECT_EQ(branchAt(root.filePath(QStringLiteral("wt"))), QStringLiteral("APP-1-login"));

  // Detached HEAD names no branch.
  ASSERT_TRUE(head.open(QIODevice::WriteOnly | QIODevice::Truncate));
  head.write("0123456789abcdef0123456789abcdef01234567\n");
  head.close();
  EXPECT_EQ(branchAt(root.filePath(QStringLiteral("repo"))), QString());
}

// ── add / done through a headless controller ──────────────────────────────

class CliHeadlessTest : public ::testing::Test {
 protected:
  void SetUp() override {
    QFile::remove(dataFile());
  }
};

TEST_F(CliHeadlessTest, AddParsesLikeQuickCaptureAndSaves) {
  const QDateTime now(QDate(2026, 10, 6), QTime(9, 0));
  {
    AppController c;
    Request r;
    r.verb = Verb::Add;
    r.text = QStringLiteral("fix login tomorrow 14:00 p1 #backend // check the tokens");
    const Response resp = execute(c, r, now);
    EXPECT_EQ(resp.exitCode, kExitOk) << qPrintable(resp.err);
    EXPECT_TRUE(resp.out.startsWith(QStringLiteral("Added "))) << qPrintable(resp.out);
    c.flushSave();
  }
  const Snapshot s = reload();
  const int pi = findProfile(s, QString());
  ASSERT_GE(pi, 0);
  // A fresh data dir gets an empty workspace, not the demo.
  ASSERT_EQ(s.profiles.at(pi).tasks.size(), 1);
  const Task& t = s.profiles.at(pi).tasks.at(0);
  EXPECT_EQ(t.title, QStringLiteral("fix login"));
  EXPECT_EQ(t.desc, QStringLiteral("check the tokens"));
  EXPECT_EQ(t.priority, QStringLiteral("P1"));
  ASSERT_EQ(t.labels.size(), 1);
  EXPECT_EQ(t.labels.at(0).id, QStringLiteral("backend"));
  EXPECT_EQ(t.dueAt, QDateTime(QDate(2026, 10, 7), QTime(14, 0)));
  EXPECT_TRUE(t.dueHasTime);
  EXPECT_TRUE(t.statusChangedAt.isValid());
}

TEST_F(CliHeadlessTest, AddUsesTheTicketKeyAndNumbersTheRest) {
  {
    AppController c;
    Request r;
    r.verb = Verb::Add;
    r.text = QStringLiteral("LTE-2398 review the patch");
    EXPECT_EQ(execute(c, r, QDateTime::currentDateTime()).exitCode, kExitOk);
    r.text = QStringLiteral("LTE-2398 follow up");  // the key is taken now
    EXPECT_EQ(execute(c, r, QDateTime::currentDateTime()).exitCode, kExitOk);
    r.text = QStringLiteral("tomorrow");  // a date and nothing else
    EXPECT_EQ(execute(c, r, QDateTime::currentDateTime()).exitCode, kExitUsage);
    c.flushSave();
  }
  const Snapshot s = reload();
  const ProfileData& p = s.profiles.at(findProfile(s, QString()));
  ASSERT_EQ(p.tasks.size(), 2);
  EXPECT_TRUE(findTask(s, QStringLiteral("LTE-2398"), 0).found());
  const TaskRef second = findTask(s, QStringLiteral("TASK-1"), 0);
  ASSERT_TRUE(second.found());
  EXPECT_TRUE(p.tasks.at(second.task).title.contains(QStringLiteral("LTE-2398")));
}

TEST_F(CliHeadlessTest, DoneMovesToDoneAndIsIdempotent) {
  {
    AppController c;
    Request add;
    add.verb = Verb::Add;
    add.text = QStringLiteral("ship it");
    ASSERT_EQ(execute(c, add, QDateTime::currentDateTime()).exitCode, kExitOk);
    Request done;
    done.verb = Verb::Done;
    done.taskId = QStringLiteral("task-1");  // any case
    const Response first = execute(c, done, QDateTime::currentDateTime());
    EXPECT_EQ(first.exitCode, kExitOk) << qPrintable(first.err);
    EXPECT_TRUE(first.out.startsWith(QStringLiteral("Done TASK-1"))) << qPrintable(first.out);
    EXPECT_TRUE(execute(c, done, QDateTime::currentDateTime()).out.startsWith(QStringLiteral("Already done")));
    done.taskId = QStringLiteral("NOPE-9");
    EXPECT_EQ(execute(c, done, QDateTime::currentDateTime()).exitCode, kExitNotFound);
    c.flushSave();
  }
  const Snapshot s = reload();
  const TaskRef ref = findTask(s, QStringLiteral("TASK-1"), 0);
  ASSERT_TRUE(ref.found());
  EXPECT_EQ(s.profiles.at(ref.profile).tasks.at(ref.task).status, QStringLiteral("done"));
}

TEST_F(CliHeadlessTest, AddToAnotherProfileLeavesTheActiveOne) {
  QString other;
  {
    AppController c;
    const QString active = c.activeProfileId();
    other = c.createProfile(QStringLiteral("Side"));
    c.setActiveProfileId(active);
    Request r;
    r.verb = Verb::Add;
    r.text = QStringLiteral("side quest");
    r.profile = QStringLiteral("side");
    const Response resp = execute(c, r, QDateTime::currentDateTime());
    EXPECT_EQ(resp.exitCode, kExitOk) << qPrintable(resp.err);
    EXPECT_EQ(c.activeProfileId(), active);
    r.profile = QStringLiteral("nowhere");
    EXPECT_EQ(execute(c, r, QDateTime::currentDateTime()).exitCode, kExitNotFound);
    c.flushSave();
  }
  const Snapshot s = reload();
  const int side = findProfile(s, other);
  ASSERT_GE(side, 0);
  ASSERT_EQ(s.profiles.at(side).tasks.size(), 1);
  EXPECT_EQ(s.profiles.at(side).tasks.at(0).title, QStringLiteral("side quest"));
}

int main(int argc, char** argv) {
  QStandardPaths::setTestModeEnabled(true);
  const QCoreApplication app(argc, argv);
  const QTemporaryDir data;
  heap::paths::setDataDir(data.path());
  AppController::setHeadless(true);
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
