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
