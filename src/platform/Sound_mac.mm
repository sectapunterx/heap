#include "platform/Sound.h"

#import <AppKit/AppKit.h>

#include <map>

namespace heap::platform::detail {

bool playWav(const QByteArray& wav, const QString& key) {
  // One NSSound per buffer for the life of the process (manual retain/release:
  // the +1 from alloc is the reference we keep). Stopping the last one lets a
  // quick second sound cut the first short, the way PlaySound does on Windows.
  static std::map<QString, NSSound*> sounds;
  static NSSound* last = nil;
  @autoreleasepool {
    NSSound* sound = nil;
    const auto it = sounds.find(key);
    if(it != sounds.end()) {
      sound = it->second;
    } else {
      NSData* data = [NSData dataWithBytes:wav.constData() length:static_cast<NSUInteger>(wav.size())];
      sound = [[NSSound alloc] initWithData:data];
      if(sound == nil) {
        return false;
      }
      sounds.emplace(key, sound);
    }
    if(last != nil) {
      [last stop];
    }
    last = sound;
    return [sound play] == YES;
  }
}

bool systemBusy() {
  // macOS keeps Focus state private to the system; heap's own quiet hours and
  // focus mode still apply.
  return false;
}

}  // namespace heap::platform::detail
