#include "platform/Sound.h"

#import <AppKit/AppKit.h>

namespace heap::platform::detail {

bool playWav(const QByteArray& wav) {
  // One NSSound for the life of the process (manual retain/release: the
  // +1 from alloc is the reference we keep). Restarting it lets a quick second
  // tick cut the first short, the way PlaySound does on Windows.
  static NSSound* sound = nil;
  @autoreleasepool {
    if(sound == nil) {
      NSData* data = [NSData dataWithBytes:wav.constData() length:static_cast<NSUInteger>(wav.size())];
      sound = [[NSSound alloc] initWithData:data];
      if(sound == nil) {
        return false;
      }
    }
    [sound stop];
    return [sound play] == YES;
  }
}

}  // namespace heap::platform::detail
