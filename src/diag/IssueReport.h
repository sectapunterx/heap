#pragma once

#include <QString>

// What "Report an issue" is allowed to put in a URL (audit PLAT-28).
//
// The report opens github.com/…/issues/new with the body in the query string,
// and a query string is not private: it lands in browser history, sync, proxy
// logs, and GitHub's own request logs before the user has decided to submit
// anything. The log tail used to go there whole — five kilobytes carrying the
// Windows user name in every path. Now only a short, scrubbed tail goes in the
// URL; the full (also scrubbed) diagnostics go to the clipboard, where the user
// can choose to paste them.

namespace heap::diag {

// `text` with the home directory replaced by "~" (either slash direction, any
// case, as Windows paths come) and any remaining whole-word occurrence of the
// user name replaced by "<user>". A user name shorter than three characters is
// left alone: replacing "al" would shred ordinary words.
QString scrubPersonalPaths(const QString& text, const QString& homePath, const QString& userName);

// The last `maxLines` whole lines of `text`, then cut to at most `maxChars`
// from the end on a line boundary where one exists.
QString tailLines(const QString& text, int maxLines, int maxChars);

// The login name of the current user, from the environment ("USERNAME" on
// Windows, "USER" elsewhere). Empty when neither is set.
QString currentUserName();

}  // namespace heap::diag
