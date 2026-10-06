#pragma once

#include <QStringList>

// The process side of the command line (APP-173): what main() hands a verb to
// before any GUI application object exists.
namespace heap::cli {

// True when `args` (argv without the program name) is a verb, --help or
// --version rather than a window launch. See VerbScan.h.
bool isCommandLine(int argc, char** argv);

// Runs the verb and returns the process exit code. Creates its own
// QCoreApplication; never opens a window. With heap already open on the data
// directory the verb is sent to it over the single-instance socket; otherwise
// it is answered from state.json (read-only verbs) or applied by a headless
// AppController that saves and exits (add, done). `open` with no window starts
// one, detached, on that task.
int run(int argc, char** argv);

// The hidden window-launch option `open` uses to start heap on a task.
inline constexpr const char* kOpenTaskOption = "open-task";

}  // namespace heap::cli
