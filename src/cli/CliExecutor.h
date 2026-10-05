#pragma once

#include "cli/CliCore.h"

#include <QDateTime>

class AppController;

namespace heap::cli {

// Answers a verb against a live AppController: the window's own (a request
// over the single-instance socket) or a headless one a `heap` run built on the
// same data directory. Mutations go through the controller's own entry points
// — quickTaskDraft + saveTask for add, moveTask for done — so ids, ranks,
// statusChangedAt, recurrence, undo and the save are exactly what the UI gets.
// A verb aimed at another profile switches to it for the change and back
// (which, like any profile switch, ends the window's undo history).
//
// `open` emits openTaskRequested; the window brings itself forward on it.
// Does not flush the save; a headless caller does that before exiting.
Response execute(AppController& controller, const Request& request, const QDateTime& now);

}  // namespace heap::cli
