// Where a mirrored card stands against its tracker, and what a pull does with
// its column (APP-163).

#include "integrations/SyncState.h"

#include <gtest/gtest.h>

using heap::integrations::mergeStatusOnPull;
using heap::integrations::StatusPull;
using heap::integrations::SyncFacts;
using heap::integrations::SyncState;
using heap::integrations::syncStateName;
using heap::integrations::syncStateOf;

TEST(SyncState, NothingOutstandingIsSynced) {
  EXPECT_EQ(syncStateOf({}), SyncState::Synced);
  EXPECT_EQ(syncStateName(SyncState::Synced), QStringLiteral("synced"));
}

TEST(SyncState, Transitions) {
  SyncFacts f;
  // The user moves the card: the write goes out.
  f.pushing = true;
  EXPECT_EQ(syncStateOf(f), SyncState::Pushing);
  // The tracker refuses it.
  f.pushing = false;
  f.unsyncedStatus = QStringLiteral("done");
  EXPECT_EQ(syncStateOf(f), SyncState::Error);
  // Retried while offline: it waits for the next sync.
  f.queued = true;
  EXPECT_EQ(syncStateOf(f), SyncState::Queued);
  // Meanwhile the tracker moved the issue too.
  f.conflicts = {QStringLiteral("status")};
  EXPECT_EQ(syncStateOf(f), SyncState::Conflict);
  // The user picks a side and the push lands.
  f = {};
  EXPECT_EQ(syncStateOf(f), SyncState::Synced);
}

TEST(SyncState, ConflictOutranksGoneAndGoneOutranksPushing) {
  SyncFacts f;
  f.gone = true;
  f.pushing = true;
  EXPECT_EQ(syncStateOf(f), SyncState::Gone);
  f.conflicts = {QStringLiteral("title")};
  EXPECT_EQ(syncStateOf(f), SyncState::Conflict);
}

TEST(SyncState, Names) {
  EXPECT_EQ(syncStateName(SyncState::Pushing), QStringLiteral("pushing"));
  EXPECT_EQ(syncStateName(SyncState::Queued), QStringLiteral("queued"));
  EXPECT_EQ(syncStateName(SyncState::Error), QStringLiteral("error"));
  EXPECT_EQ(syncStateName(SyncState::Conflict), QStringLiteral("conflict"));
  EXPECT_EQ(syncStateName(SyncState::Gone), QStringLiteral("gone"));
}

// local, unsynced, prevRemote, remote, mapped, lastColumn

TEST(StatusPull, RemoteMoveWithNothingUnsentWins) {
  EXPECT_EQ(mergeStatusOnPull("prog", "", "open", "closed", "done", "todo"), StatusPull::TakeRemote);
}

TEST(StatusPull, RemoteMoveAgainstAnUnsentLocalMoveIsAConflict) {
  // Moved to Done here, the push was refused; meanwhile someone moved the
  // issue to In Review in the tracker. Neither side is dropped silently.
  EXPECT_EQ(mergeStatusOnPull("done", "done", "In Progress", "In Review", "review", "prog"), StatusPull::Conflict);
}

TEST(StatusPull, BothSidesAgreeIsNoConflict) {
  EXPECT_EQ(mergeStatusOnPull("done", "done", "open", "closed", "done", "todo"), StatusPull::TakeRemote);
}

TEST(StatusPull, UnsentMoveSurvivesAQuietPull) {
  EXPECT_EQ(mergeStatusOnPull("done", "done", "open", "open", "todo", "todo"), StatusPull::Keep);
}

TEST(StatusPull, UsersArrangementStands) {
  // Remote unchanged, card moved since the last pull: keep it.
  EXPECT_EQ(mergeStatusOnPull("blocked", "", "open", "open", "todo", "todo"), StatusPull::Keep);
  // Still where the pull put it: follow a changed mapping.
  EXPECT_EQ(mergeStatusOnPull("todo", "", "open", "open", "backlog", "todo"), StatusPull::TakeRemote);
}

TEST(StatusPull, LegacyCardOnlyFollowsAChangeOfKind) {
  EXPECT_EQ(mergeStatusOnPull("prog", "", "", "open", "todo", ""), StatusPull::Keep);
  EXPECT_EQ(mergeStatusOnPull("prog", "", "", "closed", "done", ""), StatusPull::TakeRemote);
}
