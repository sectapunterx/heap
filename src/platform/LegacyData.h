#pragma once

#include <QString>

#include <cstdint>

// The one-time move of a 0.7.x data folder (…/heap/heap) to the lowkey one
// (…/lowkey/lowkey), APP-280. A copy, not a move: the old folder keeps its
// files plus a marker saying where they went, so a downgrade still finds them
// and a second launch does not copy again. Nothing here runs for a redirected
// data folder (--data-dir, HEAP_DATA_DIR) or a smoke run.
namespace heap::platform::legacy {

enum class MoveKind : std::uint8_t {
  NothingToDo,  // the new folder already has a state.json, or there is no old one
  Moved,        // the old folder's files were copied over
  Busy,         // an old heap still runs on the old folder: copy nothing yet
  Failed,       // a file could not be copied; the new folder is left as it was
};

struct MoveResult {
  MoveKind kind = MoveKind::NothingToDo;
  QString from;
  QString to;
  QString error;
  int files = 0;
};

// The 0.7.x folder that sits beside `newDir`: <base>/lowkey/lowkey →
// <base>/heap/heap. Empty when `newDir` does not end in the new names.
QString legacyDirFor(const QString& newDir);

// Copies `legacyDir` into `newDir` once. Lock files are not copied; anything
// already in `newDir` (a log written this launch) is kept. All-or-nothing:
// the files are copied to a sibling folder first and moved in at the end.
MoveResult moveLegacyData(const QString& newDir, const QString& legacyDir);

}  // namespace heap::platform::legacy
