#pragma once

#include <filesystem>
#include <string>

// The file work of heap-updater (APP-125), kept free of Qt and Win32 so it
// links into the tests on every platform. heap-updater itself is Windows-only:
// there a running heap.exe and its DLLs cannot be overwritten, so the swap
// waits for heap to quit and happens in a separate process.
namespace heap::updater {

// Put every top-level entry of `staging` (an unpacked portable zip) into
// `target`. An entry already there is first moved aside into
// `target/.heap-update-old`; if anything fails midway, what was copied is
// removed and what was moved aside is put back, so `target` is the old
// version again. Entries of `target` the new version does not ship (the
// user's own files, a --data-dir inside the folder) are not touched.
// On success the moved-aside copy is deleted. Returns false and fills `error`
// on failure.
bool swapBundle(const std::filesystem::path& staging, const std::filesystem::path& target, std::string& error);

}  // namespace heap::updater
