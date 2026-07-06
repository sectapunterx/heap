#include "platform/MacWindow.h"

#include <QWindow>

#import <AppKit/AppKit.h>

namespace heap::platform {

void applyUnifiedTitlebar(QWindow* window) {
  if(!window) {
    return;
  }
  // winId() materializes the NSView that backs the QWindow; its containing
  // NSWindow is the one we restyle.
  NSView* view = reinterpret_cast<NSView*>(window->winId());
  NSWindow* nsWindow = view ? [view window] : nil;
  if(!nsWindow) {
    return;
  }

  // Transparent title bar + full-size content view: the content fills up under
  // the title bar so the app's top strip and the traffic lights share one band.
  // The title bar itself still exists (just invisible), so its drag region and
  // the standard window buttons keep working.
  nsWindow.titlebarAppearsTransparent = YES;
  nsWindow.titleVisibility = NSWindowTitleHidden;
  nsWindow.styleMask |= NSWindowStyleMaskFullSizeContentView;

  // Let the user drag the window from any empty part of the top bar, not only
  // the thin native title-bar strip. Interactive controls still receive clicks.
  nsWindow.movableByWindowBackground = YES;

  // Belt-and-braces: keep the traffic lights visible over the content.
  [[nsWindow standardWindowButton:NSWindowCloseButton] setHidden:NO];
  [[nsWindow standardWindowButton:NSWindowMiniaturizeButton] setHidden:NO];
  [[nsWindow standardWindowButton:NSWindowZoomButton] setHidden:NO];
}

}  // namespace heap::platform
