#include "updater/BundleSwap.h"

#include <system_error>
#include <vector>

namespace fs = std::filesystem;

namespace heap::updater {

namespace {

constexpr auto kBackupDir = ".heap-update-old";

struct Placed {
  fs::path dst;
  bool movedAside = false;  // an older copy sits in the backup folder
  bool copied = false;      // the new copy is in place
};

void rollBack(const std::vector<Placed>& placed, const fs::path& backup) {
  for(auto it = placed.rbegin(); it != placed.rend(); ++it) {
    std::error_code ec;
    if(it->copied) {
      fs::remove_all(it->dst, ec);
    }
    if(it->movedAside) {
      fs::rename(backup / it->dst.filename(), it->dst, ec);
    }
  }
}

}  // namespace

bool swapBundle(const fs::path& staging, const fs::path& target, std::string& error) {
  std::error_code ec;
  if(!fs::is_directory(staging, ec) || fs::is_empty(staging, ec)) {
    error = "the unpacked update is empty";
    return false;
  }
  if(!fs::is_directory(target, ec)) {
    error = "the install folder is gone: " + target.string();
    return false;
  }
  const fs::path backup = target / kBackupDir;
  fs::remove_all(backup, ec);  // what an interrupted earlier run left
  fs::create_directories(backup, ec);
  if(ec) {
    error = "cannot write to " + target.string() + ": " + ec.message();
    return false;
  }

  std::vector<Placed> placed;
  for(const fs::directory_entry& entry : fs::directory_iterator(staging, ec)) {
    const fs::path name = entry.path().filename();
    if(name == kBackupDir) {
      continue;
    }
    Placed p;
    p.dst = target / name;
    if(fs::exists(p.dst, ec)) {
      fs::rename(p.dst, backup / name, ec);
      if(ec) {
        error = "cannot move " + p.dst.string() + " aside: " + ec.message();
        rollBack(placed, backup);
        fs::remove_all(backup, ec);
        return false;
      }
      p.movedAside = true;
    }
    // Marked copied before the copy: a partial one has to go too.
    p.copied = true;
    placed.push_back(p);
    fs::copy(entry.path(), p.dst, fs::copy_options::recursive | fs::copy_options::overwrite_existing, ec);
    if(ec) {
      error = "cannot copy " + name.string() + ": " + ec.message();
      rollBack(placed, backup);
      fs::remove_all(backup, ec);
      return false;
    }
  }
  if(ec) {
    error = "cannot read the unpacked update: " + ec.message();
    rollBack(placed, backup);
    fs::remove_all(backup, ec);
    return false;
  }
  fs::remove_all(backup, ec);  // best effort: a leftover is cleared next time
  return true;
}

}  // namespace heap::updater
