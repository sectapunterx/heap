#pragma once

class QWindow;

namespace heap::platform {

// Give the macOS window a unified, full-size-content-view title bar: the native
// title bar turns transparent and the QML content extends up under it, so the
// app's own top bar visually hosts the traffic-light buttons instead of sitting
// below a separate title bar. The window stays draggable by its background.
//
// Only compiled + linked on macOS (see CMakeLists). Safe to call once, after the
// window's native handle exists.
void applyUnifiedTitlebar(QWindow* window);

}  // namespace heap::platform
