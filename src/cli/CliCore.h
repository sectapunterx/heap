#pragma once

#include "Models.h"

#include <QByteArray>
#include <QDate>
#include <QDateTime>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVector>

#include <cstdint>
#include <optional>

// The command line (APP-173): `heap add|now|list|today|done|open|help`.
//
// heap is a helper here as everywhere: these verbs carry a task in or out of
// the terminal and nothing more. Everything in this file is pure — argument
// parsing, the wire format between a `heap` run and the window already open on
// the same data directory, the read-only questions (`now`, `list`, `today`)
// over a snapshot of the profiles, and how answers are printed — so the window
// and a headless run answer from the same code. Mutations go through
// AppController (see CliExecutor.h).
namespace heap::cli {

// Process exit codes of a verb.
inline constexpr int kExitOk = 0;
inline constexpr int kExitUsage = 1;     // the command line is wrong
inline constexpr int kExitNotFound = 2;  // no such task, profile or column
inline constexpr int kExitData = 3;      // state.json unreadable, a save failed, the window did not answer

enum class Verb : std::uint8_t { Help, Version, Add, Now, List, Today, Done, Open };

struct Request {
  Verb verb = Verb::Help;
  QString text;     // add: the capture text
  QString taskId;   // done/open: the task asked for
  QString profile;  // --profile: a profile name or id ("" = the active one)
  QString status;   // list --status: a column id or name
  QString format;   // now --format
  bool json = false;
  // now: the branch checked out in the caller's working directory. Read by the
  // caller, because the window's own working directory is somewhere else.
  QString branch;
};

struct Response {
  int exitCode = kExitOk;
  QString out;  // for stdout, newline-terminated when not empty
  QString err;  // for stderr
};

struct ParsedArgs {
  bool ok = false;
  QString error;  // why not, for "heap: <error>"
  Request request;
  QString dataDir;
  bool dataDirSet = false;
};

// Parses a verb's command line (`args` without the program name). --data-dir
// is accepted anywhere, as for a window launch.
ParsedArgs parseArgs(const QStringList& args);

// The usage text printed by `heap help` and `heap --help`. ASCII only: it is
// printed straight to consoles whose code page is not guaranteed.
QString helpText();

// ── Wire format ──────────────────────────────────────────────────────────
// One line of compact JSON each way over the single-instance socket. A line
// that does not start with '{' is the older plain "activate …" message.
QByteArray encodeRequest(const Request& r);
std::optional<Request> decodeRequest(const QByteArray& line);
QByteArray encodeResponse(const Response& r);
std::optional<Response> decodeResponse(const QByteArray& line);

// ── Snapshot of the data ─────────────────────────────────────────────────
struct ProfileData {
  QString id;
  QString name;
  QVector<Task> tasks;
  QVariantList statuses;  // [{id, name, doing, …}] in board order
};

struct Snapshot {
  QVector<ProfileData> profiles;
  QString activeProfileId;
  QString idPrefix = QStringLiteral("TASK");  // settings → tasks → idPrefix, uppercased
};

Snapshot snapshotFromProfiles(const QVector<Profile>& profiles, const QString& activeProfileId, const QString& idPrefix);

// Reads a parsed state.json read-only (an older schema is migrated in memory,
// never written back). Empty when the document has no profiles array — a
// pre-profile state that only the window knows how to upgrade.
std::optional<Snapshot> snapshotFromState(QJsonObject root, QString* error = nullptr);

// ── Questions ────────────────────────────────────────────────────────────
// The profile `wanted` names (id, then name, case-insensitively), or the
// active one when `wanted` is empty. -1 when there is none.
int findProfile(const Snapshot& s, const QString& wanted);

struct TaskRef {
  int profile = -1;
  int task = -1;

  bool found() const {
    return profile >= 0 && task >= 0;
  }
};

// The task `query` names: its id (exact, then any case) or, for a mirrored
// issue, the tracker key ("PROJ-12", "#42"). Profile `preferred` is searched
// first, then the others.
TaskRef findTask(const Snapshot& s, const QString& query, int preferred);

// What `heap now` reports, in this order: the task whose timer is running
// (the active profile first, then the others; the most recently started
// wins), else the task the checked-out `branch` names in the active profile,
// else nothing. Archived tasks never count.
struct NowResult {
  TaskRef ref;
  QString source;  // "timer" | "branch" | "" (nothing)
};

NowResult resolveNow(const Snapshot& s, const QString& branch);

// A column's display name, or the id when the column is unknown.
QString statusName(const QVariantList& statuses, const QString& statusId);
// In Progress, or a column the user marked as "doing".
bool isDoingStatus(const QVariantList& statuses, const QString& statusId);
// The column `wanted` names (id, then name, case-insensitively), or "".
QString findStatus(const QVariantList& statuses, const QString& wanted);
// The column a finished task goes to: "done" when the board has it, else the
// last column.
QString doneStatus(const QVariantList& statuses);

// Unarchived tasks of `p` (only column `statusId` when given), in board order:
// by column, then by the manual rank within it.
QVector<int> listTasks(const ProfileData& p, const QString& statusId);
// What is on today's plate: unarchived, not done, and either in a "doing"
// column or scheduled or due on `today`.
QVector<int> todayTasks(const ProfileData& p, const QDate& today);

// ── Output ───────────────────────────────────────────────────────────────
QJsonObject taskJson(const ProfileData& p, const Task& t, const QDateTime& now);
// Aligned "ID  [Column]  P1  title  (due …)" lines, one per task.
QString taskLines(const ProfileData& p, const QVector<int>& rows);
// Expands {id} {title} {status} {priority} {profile} {source} {elapsed} in
// `format`; "{id} {title}" when `format` is empty.
QString formatNow(const QString& format, const ProfileData& p, const Task& t, const QString& source, const QDateTime& now);

// Answers a read-only verb (now, list, today) from `s`.
Response answer(const Snapshot& s, const Request& r, const QDateTime& now);

// The branch checked out in the git work tree containing `dir`: HEAD read
// straight from the repository (no git process — `heap now` runs in a shell
// prompt). "" outside a repository or on a detached HEAD.
QString branchAt(const QString& dir);

}  // namespace heap::cli
