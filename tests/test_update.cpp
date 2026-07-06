// Unit tests for heap::update::isNewerVersion — the semver comparison behind the
// GitHub-Releases update check (HEAP-63). Pure function, no network.

#include "update/Updater.h"

#include <gtest/gtest.h>

using heap::update::isNewerVersion;

TEST(UpdateVersionCompare, DetectsNewer) {
  EXPECT_TRUE(isNewerVersion("0.4.2", "0.5.0"));
  EXPECT_TRUE(isNewerVersion("0.4.2", "v0.4.3"));
  EXPECT_TRUE(isNewerVersion("v0.4.2", "0.10.0"));  // 10 > 4, not lexicographic
  EXPECT_TRUE(isNewerVersion("1.0.0", "1.0.1"));
}

TEST(UpdateVersionCompare, RejectsSameOrOlder) {
  EXPECT_FALSE(isNewerVersion("0.4.2", "0.4.2"));
  EXPECT_FALSE(isNewerVersion("0.5.0", "0.4.9"));
  EXPECT_FALSE(isNewerVersion("v1.2.3", "v1.2.3"));
  EXPECT_FALSE(isNewerVersion("0.4.2", "v0.4.1"));
}

TEST(UpdateVersionCompare, HandlesPrerelease) {
  // Equal numeric core: a plain release outranks its pre-release.
  EXPECT_TRUE(isNewerVersion("1.0.0-rc1", "1.0.0"));
  EXPECT_FALSE(isNewerVersion("1.0.0", "1.0.0-rc1"));
  // A higher numeric core still wins regardless of pre-release suffix.
  EXPECT_TRUE(isNewerVersion("1.0.0", "1.0.1-rc1"));
}

TEST(UpdateVersionCompare, HandlesDifferentComponentCounts) {
  EXPECT_TRUE(isNewerVersion("1.0", "1.0.1"));
  EXPECT_FALSE(isNewerVersion("1.0.0", "1.0"));
  EXPECT_FALSE(isNewerVersion("1", "1.0.0"));
}

TEST(UpdateVersionCompare, DevBuildRanksBelowMatchingRelease) {
  // The Release workflow names manual test builds vX.Y.Z-dev.<sha> — a SemVer
  // pre-release of the same numeric core. A user on that dev build must be
  // offered the matching real release, and a user already on the release must
  // NOT be offered a dev build of the same version. This is the contract the CI
  // naming scheme relies on (see .github/workflows/release.yml meta job).
  EXPECT_TRUE(isNewerVersion("1.0.0-dev.abc1234", "v1.0.0"));
  EXPECT_FALSE(isNewerVersion("1.0.0", "v1.0.0-dev.abc1234"));
  // A newer real release still outranks an older dev build.
  EXPECT_TRUE(isNewerVersion("1.0.0-dev.abc1234", "v1.1.0"));
}
