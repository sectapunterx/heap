#pragma once

#include <QString>

// What the operating system says about motion and contrast, read once for a
// new profile's defaults (design audit DES-23): heap's own "Reduce motion" and
// "High contrast" started off whatever the user had asked Windows for.
namespace heap::platform {

struct AccessibilityPrefs {
  bool reduce_motion = false;
  bool high_contrast = false;
};

// Windows: "Show animations in Windows" off → reduce_motion, a high-contrast
// theme on → high_contrast. Elsewhere both are false for now.
AccessibilityPrefs systemAccessibilityPrefs();

// The appearance a new profile starts with: heap. ink / heap. light, soft
// contrast — or high contrast and no motion when the system asks for them.
// Pure, so the choice is testable without the system settings.
QString firstRunAppearanceJson(const AccessibilityPrefs& prefs);

}  // namespace heap::platform
