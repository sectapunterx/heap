#pragma once

#include <QString>
#include <QStringList>

#include <cstdint>

// Where a mirrored card stands against its tracker (APP-163), and how a pull
// treats the card's status. Pure: AppController feeds it the facts it already
// keeps (ExternalMeta plus the runtime push bookkeeping), so the rules can be
// tested without a provider or a model. Header-only because Models.cpp, which
// uses it, is compiled into several test targets on its own.
namespace heap::integrations {

enum class SyncState : std::uint8_t {
  Synced,    // nothing outstanding
  Pushing,   // a status write is on its way to the tracker
  Queued,    // a move waits for the tracker to be reachable again
  Error,     // the tracker refused the last move
  Conflict,  // a field changed both here and in the tracker
  Gone,      // the issue was missing from the last complete pull
};

struct SyncFacts {
  bool pushing = false;    // a push is in flight
  bool queued = false;     // ExternalMeta::pushQueued
  QString unsyncedStatus;  // ExternalMeta::unsyncedStatus
  QStringList conflicts;   // ExternalMeta::conflicts
  bool gone = false;       // ExternalMeta::goneUpstream
};

// The one state a card shows. A conflict outranks everything (it needs a
// decision), then a vanished issue, then a write in flight, then a refusal,
// then a queued move.
inline SyncState syncStateOf(const SyncFacts& f) {
  if(!f.conflicts.isEmpty()) {
    return SyncState::Conflict;
  }
  if(f.gone) {
    return SyncState::Gone;
  }
  if(f.pushing) {
    return SyncState::Pushing;
  }
  if(!f.unsyncedStatus.isEmpty()) {
    return f.queued ? SyncState::Queued : SyncState::Error;
  }
  return SyncState::Synced;
}

// "synced" | "pushing" | "queued" | "error" | "conflict" | "gone", for QML.
inline QString syncStateName(SyncState s) {
  switch(s) {
    case SyncState::Pushing:
      return QStringLiteral("pushing");
    case SyncState::Queued:
      return QStringLiteral("queued");
    case SyncState::Error:
      return QStringLiteral("error");
    case SyncState::Conflict:
      return QStringLiteral("conflict");
    case SyncState::Gone:
      return QStringLiteral("gone");
    case SyncState::Synced:
      break;
  }
  return QStringLiteral("synced");
}

// What a pull does with a card's column.
enum class StatusPull : std::uint8_t {
  Keep,        // the column the user chose stands
  TakeRemote,  // follow the tracker
  Conflict,    // the tracker moved while a local move was still unsent: keep
               // the local column and ask the user
};

// `local` is the card's column, `unsynced` the move heap has not got into the
// tracker yet (refused or queued), `prevRemote` the tracker status the last
// pull saw ("" = unknown), `remote` the status it sends now, `mapped` that
// status as a column, `lastColumn` the column the last pull put the card in.
//
// The tracker moving an issue whose card carries no unsent move is news and
// wins. Moving it while a local move was unsent used to win silently too, and
// the local move was dropped; now the local column is kept and the user
// picks — unless both sides already agree.
inline StatusPull mergeStatusOnPull(const QString& local,
                                    const QString& unsynced,
                                    const QString& prevRemote,
                                    const QString& remote,
                                    const QString& mapped,
                                    const QString& lastColumn) {
  const bool remoteMoved = !prevRemote.isEmpty() && prevRemote != remote;
  if(remoteMoved) {
    // Nothing of ours was waiting, or both sides already agree.
    return (unsynced.isEmpty() || mapped == local) ? StatusPull::TakeRemote : StatusPull::Conflict;
  }
  if(!unsynced.isEmpty()) {
    // A move the tracker has not taken yet: keep it here until a push lands.
    return StatusPull::Keep;
  }
  if(prevRemote.isEmpty()) {
    // Stored before the last-seen status was kept. Only a change of kind
    // (open ↔ closed) is evidence; the rest is the user's arrangement.
    const bool localDone = local == QLatin1String("done");
    const bool remoteDone = mapped == QLatin1String("done");
    return localDone != remoteDone ? StatusPull::TakeRemote : StatusPull::Keep;
  }
  // Still where the last pull put it, so the user has not placed it: follow
  // the mapping, which may have changed since.
  return local == lastColumn ? StatusPull::TakeRemote : StatusPull::Keep;
}

}  // namespace heap::integrations
