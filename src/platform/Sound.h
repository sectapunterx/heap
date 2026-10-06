#pragma once

#include <QByteArray>
#include <QString>

// The opt-in completion sound (APP-167): a short soft tick when the user moves
// a task to Done. No QtMultimedia — each platform plays the bundled WAV with
// what it already has:
//   Windows → PlaySoundW(SND_MEMORY | SND_ASYNC) from winmm.
//   macOS   → NSSound.
//   Linux   → a detached `paplay` (or `aplay -q`) on a cached copy of the file;
//             silent when neither is installed.
namespace heap::platform {

// Who moved the task. Only the user's own action in this window makes a sound:
// a tracker sync, an undo/redo and a `heap done` from a shell stay quiet.
enum class StatusChangeSource { User, Sync, Undo, Cli };

// The task's status id the board treats as finished.
inline constexpr const char* kDoneStatusId = "done";

// Pure: does this status change earn the sound? `enabled` is the Appearance
// setting (appearance.completionSound, off by default).
bool shouldPlayCompletionSound(const QString& fromStatus, const QString& toStatus, StatusChangeSource source, bool enabled);

// The bundled sound (qrc :/sounds/complete.wav), loaded once.
const QByteArray& completionSoundWav();

// Plays the sound. Asynchronous and non-blocking, never throws, and a no-op in
// QStandardPaths test mode and while suppressed (--smoke).
void playCompletionSound();

// main() sets this for --smoke: the UI runs, but nothing should make noise.
void setSoundSuppressed(bool suppressed);

// How many times playCompletionSound() was asked to play, counted before the
// test-mode / suppression check — lets the tests see the call was made.
int completionSoundRequestCount();

namespace detail {
// The platform backend: returns whether playback was started.
bool playWav(const QByteArray& wav);
}  // namespace detail

}  // namespace heap::platform
