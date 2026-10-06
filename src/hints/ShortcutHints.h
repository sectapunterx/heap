#pragma once

#include <QJsonObject>
#include <QString>

// "There is a key for that" (APP-166). An action that has a keyboard shortcut
// and keeps being reached with the mouse gets one quiet line naming the key —
// on the third mouse use, once, and never again for that action. Counted per
// catalogue id; the counts live in state.json under settings.shortcutHints so
// "once" survives a restart.
namespace heap::hints {

// Mouse uses of one action before its key is mentioned.
inline constexpr int kMouseUsesBeforeHint = 3;

struct MouseUseResult {
  bool changed = false;   // `uses` was updated and wants saving
  bool showHint = false;  // this is the use the hint is for
};

// Counts a mouse use of `id` in `uses` (id -> uses so far). An action with no
// key bound right now is not counted: there would be nothing to suggest. Once
// an action reaches kMouseUsesBeforeHint it is never counted again, so the hint
// is shown exactly once. With hints switched off nothing is counted either, so
// switching them back on starts from where the user left off.
inline MouseUseResult recordMouseUse(QJsonObject& uses, const QString& id, bool hasShortcut, bool enabled) {
  MouseUseResult r;
  if(!enabled || !hasShortcut || id.isEmpty()) {
    return r;
  }
  const int n = uses.value(id).toInt(0);
  if(n >= kMouseUsesBeforeHint || n < 0) {
    return r;
  }
  uses.insert(id, n + 1);
  r.changed = true;
  r.showHint = n + 1 == kMouseUsesBeforeHint;
  return r;
}

// Settings → Shortcuts "Suggest shortcuts": app settings shortcuts.mouseHints,
// on unless switched off.
inline bool hintsEnabled(const QJsonObject& appSettings) {
  const QJsonValue v = appSettings.value(QStringLiteral("shortcuts")).toObject().value(QStringLiteral("mouseHints"));
  return !v.isBool() || v.toBool();
}

}  // namespace heap::hints
