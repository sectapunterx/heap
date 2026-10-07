#pragma once

class QWindow;

namespace heap::platform {

// Paints the window's own frame (title bar, the close/minimise buttons)
// dark or light to match heap's theme. Windows draws that frame itself and
// follows the system's app mode, so with Windows in light mode a dark heap
// sat under a white title bar. Windows 10 1809+ only; elsewhere, and on
// older Windows, a no-op.
void setWindowFrameDark(QWindow* window, bool dark);

}  // namespace heap::platform
