#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <string_view>

// Whether a command line is a command-line verb (`heap add …`, `heap now`) or a
// window launch (`heap`, `heap --view board`). Decided before any Qt object
// exists — a verb runs without a GUI application — and shared with the
// console front end on Windows (heap-cli.exe, which reads its wide command
// line), so it is plain C++ over any character type.
namespace heap::cli {

inline constexpr std::array<std::string_view, 11> kVerbs = {
    "add", "now", "list", "today", "done", "open", "sched", "due", "est", "someday", "help"};

namespace detail {

template<typename CharT>
bool equalsAscii(std::basic_string_view<CharT> arg, std::string_view ascii) {
  if(arg.size() != ascii.size()) {
    return false;
  }
  for(std::size_t i = 0; i < arg.size(); ++i) {
    if(arg[i] != static_cast<CharT>(ascii[i])) {
      return false;
    }
  }
  return true;
}

// Options that take a separate value, heap's own and the Qt switches a window
// launch may carry. Their value is never the verb.
template<typename CharT>
bool takesValue(std::basic_string_view<CharT> arg) {
  static constexpr std::array<std::string_view, 16> kValued = {
      "--data-dir",
      "--view",
      "--profile",
      "--status",
      "--format",
      "-platform",
      "-platformpluginpath",
      "-platformtheme",
      "-plugin",
      "-style",
      "-stylesheet",
      "-session",
      "-display",
      "-geometry",
      "-qwindowgeometry",
      "-qwindowtitle",
  };
  return std::any_of(kValued.begin(), kValued.end(), [arg](std::string_view v) {
    return equalsAscii(arg, v);
  });
}

}  // namespace detail

// What `args` (without the program name) asks for.
enum class Invocation : std::uint8_t {
  Window,   // start or summon the GUI
  Command,  // a verb, --help or --version: answered on the console
};

template<typename CharT, typename Range>
Invocation classify(const Range& args) {
  using View = std::basic_string_view<CharT>;
  bool skipValue = false;
  for(const auto& raw : args) {
    const View arg(raw);
    if(skipValue) {
      skipValue = false;
      continue;
    }
    if(detail::equalsAscii(arg, "--")) {
      return Invocation::Window;  // nothing after it is an option, and no verb came first
    }
    if(detail::equalsAscii(arg, "--help") || detail::equalsAscii(arg, "-h") || detail::equalsAscii(arg, "-?") ||
       detail::equalsAscii(arg, "--version") || detail::equalsAscii(arg, "-v")) {
      return Invocation::Command;
    }
    if(!arg.empty() && arg.front() == static_cast<CharT>('-')) {
      skipValue = detail::takesValue(arg);
      continue;
    }
    // The first positional argument decides.
    const bool verb = std::any_of(kVerbs.begin(), kVerbs.end(), [arg](std::string_view v) {
      return detail::equalsAscii(arg, v);
    });
    return verb ? Invocation::Command : Invocation::Window;
  }
  return Invocation::Window;
}

}  // namespace heap::cli
