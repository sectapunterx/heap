#include "platform/WindowFrame.h"

#include <QWindow>

#ifdef Q_OS_WIN
#include <dwmapi.h>
#include <windows.h>
#endif

namespace heap::platform {

void setWindowFrameDark(QWindow* window, bool dark) {
#ifdef Q_OS_WIN
  if(window == nullptr) {
    return;
  }
  auto* const hwnd = reinterpret_cast<HWND>(window->winId());
  const BOOL value = dark ? TRUE : FALSE;
  // DWMWA_USE_IMMERSIVE_DARK_MODE is 20 from Windows 10 20H1 on and was 19
  // on 1809–1909; the old id fails harmlessly on newer builds.
  constexpr DWORD kDarkModeAttr = 20;
  constexpr DWORD kDarkModeAttrBefore20H1 = 19;
  if(FAILED(DwmSetWindowAttribute(hwnd, kDarkModeAttr, &value, sizeof(value)))) {
    DwmSetWindowAttribute(hwnd, kDarkModeAttrBefore20H1, &value, sizeof(value));
  }
  // The frame keeps its old colours until Windows repaints it; a theme switch
  // while the window is open would otherwise show only after a resize.
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
#else
  (void)window;
  (void)dark;
#endif
}

}  // namespace heap::platform
