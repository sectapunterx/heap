#pragma once

#include "cli/CliCore.h"

#include <QByteArray>
#include <QString>

#include <optional>

// The part of the command line that never needs an AppController: help,
// version and the questions (now, list, today). Kept apart so the lean
// console front end on Windows (heap-cli.exe) can answer `heap now` in a
// shell prompt without loading the GUI libraries.
namespace heap::cli {

bool changesData(Verb v);

// The state.json of the current data dir, read-only. An empty snapshot when
// there is none yet; empty optional (and `error`) when it cannot be used.
std::optional<Snapshot> readSnapshot(QString* error);

// Why the state.json of the current data dir must not be loaded for a change
// from here: it cannot be read, or what it holds is not a state file. Empty
// when it is fine or there is none yet. Loading a damaged file quarantines it
// and promotes a backup (or an empty workspace); only the window may do that,
// since only the window shows the banner saying so (CLI-1).
QString unusableState();

// Sends the request to the window open on the data dir. Empty when none is.
std::optional<Response> askWindow(const QByteArray& requestLine);

// Answers help, version, now, list and today and returns the exit code; empty
// for a verb that changes data or opens the window. Expects the data dir set
// (heap::paths::setDataDir) and an application object.
std::optional<int> runQuery(Request request);

}  // namespace heap::cli
