// heap-updater (APP-125): puts a downloaded, already checksum-verified update
// in place once heap has quit, then starts heap again. Windows only: a running
// exe and its DLLs cannot be overwritten there, so the swap has to happen
// after heap exits, from a process that does not live in the folder it
// replaces (heap copies this exe to the temp folder before starting it).
//
//   heap-updater --pid <heap's pid> --mode setup|portable --package <file>
//                --target <install folder> --exe <heap.exe> --result <file>
//
// setup:    run the new Inno Setup installer silently, in the same mode (all
//           users / only me) as the install it replaces. It upgrades in place
//           (same AppId) and asks for elevation itself when per-machine.
// portable: unpack the zip with Windows' own tar.exe, then swapBundle().
//
// The outcome goes to --result ("ok" or "error\n<why>"); heap reads it on its
// next start and tells the user. heap is started again either way, so a failed
// update leaves the old version running rather than nothing.
//
// No Qt here: the exe has to run on its own from the temp folder.

#include "updater/BundleSwap.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <filesystem>
#include <fstream>
#include <map>
#include <string>

#include <windows.h>

// shellapi.h needs windows.h first.
#include <shellapi.h>

namespace fs = std::filesystem;

namespace {

constexpr DWORD kWaitForHeapMs = 2 * 60 * 1000;

std::string lastError(const char* what) {
  return std::string(what) + " (Windows error " + std::to_string(GetLastError()) + ")";
}

void writeResult(const fs::path& file, const std::string& error) {
  if(file.empty()) {
    return;
  }
  std::ofstream out(file, std::ios::binary | std::ios::trunc);
  out << (error.empty() ? std::string("ok\n") : "error\n" + error + "\n");
}

void waitForExit(DWORD pid) {
  HANDLE h = OpenProcess(SYNCHRONIZE, FALSE, pid);
  if(h == nullptr) {
    return;  // already gone
  }
  WaitForSingleObject(h, kWaitForHeapMs);
  CloseHandle(h);
}

// Run a program and wait for it. ShellExecuteEx rather than CreateProcess so a
// per-machine installer can raise the UAC prompt.
bool runAndWait(const std::wstring& file, const std::wstring& params, bool hidden, DWORD& exitCode, std::string& error) {
  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
  info.lpFile = file.c_str();
  info.lpParameters = params.c_str();
  info.nShow = hidden ? SW_HIDE : SW_SHOWNORMAL;
  if(!ShellExecuteExW(&info) || info.hProcess == nullptr) {
    error = GetLastError() == ERROR_CANCELLED ? std::string("the administrator prompt was declined")
                                              : lastError("could not start the installer");
    return false;
  }
  WaitForSingleObject(info.hProcess, INFINITE);
  GetExitCodeProcess(info.hProcess, &exitCode);
  CloseHandle(info.hProcess);
  return true;
}

std::wstring quoted(const fs::path& p) {
  return L"\"" + p.wstring() + L"\"";
}

// The installer can install for all users or only for the current one; an
// update has to stay in the mode the install it replaces used, or a per-user
// copy would be "upgraded" by a second install in Program Files. Inno Setup
// keeps a per-user install's uninstall entry under HKCU.
bool installedForCurrentUserOnly() {
  const wchar_t* key =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\"
      L"{6F4C9E2A-3B7D-4E1F-9A6C-0D2B1E8F5A44}_is1";
  HKEY h = nullptr;
  if(RegOpenKeyExW(HKEY_CURRENT_USER, key, 0, KEY_READ, &h) != ERROR_SUCCESS) {
    return false;
  }
  RegCloseKey(h);
  return true;
}

std::string installSetup(const fs::path& package) {
  DWORD code = 0;
  std::string error;
  const std::wstring scope = installedForCurrentUserOnly() ? L" /CURRENTUSER" : L" /ALLUSERS";
  if(!runAndWait(package.wstring(), L"/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" + scope, false, code, error)) {
    return error;
  }
  return code == 0 ? std::string() : "the installer exited with code " + std::to_string(code);
}

std::string installPortable(const fs::path& package, const fs::path& target) {
  const fs::path staging = package.parent_path() / L"staging";
  std::error_code ec;
  fs::remove_all(staging, ec);
  fs::create_directories(staging, ec);
  if(ec) {
    return "cannot create " + staging.string() + ": " + ec.message();
  }
  wchar_t sysDir[MAX_PATH] = {};
  GetSystemDirectoryW(sysDir, MAX_PATH);
  const fs::path tar = fs::path(sysDir) / L"tar.exe";
  DWORD code = 0;
  std::string error;
  if(!runAndWait(tar.wstring(), L"-xf " + quoted(package) + L" -C " + quoted(staging), true, code, error)) {
    return "could not start tar.exe to unpack the update";
  }
  if(code != 0) {
    return "tar.exe could not unpack the update (code " + std::to_string(code) + ")";
  }
  if(!heap::updater::swapBundle(staging, target, error)) {
    fs::remove_all(staging, ec);
    return error;
  }
  fs::remove_all(staging, ec);
  return {};
}

void relaunch(const fs::path& exe, const fs::path& dir) {
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  std::wstring cmd = quoted(exe);
  if(CreateProcessW(exe.c_str(), cmd.data(), nullptr, nullptr, FALSE, 0, nullptr, dir.c_str(), &si, &pi)) {
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
  }
}

}  // namespace

int WINAPI wWinMain(HINSTANCE /*instance*/, HINSTANCE /*previous*/, PWSTR /*cmdLine*/, int /*show*/) {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::map<std::wstring, std::wstring> args;
  for(int i = 1; argv != nullptr && i + 1 < argc; i += 2) {
    args[argv[i]] = argv[i + 1];
  }
  LocalFree(argv);

  const fs::path package = args[L"--package"];
  const fs::path target = args[L"--target"];
  const fs::path exe = args[L"--exe"];
  const fs::path result = args[L"--result"];
  const std::wstring mode = args[L"--mode"];
  if(package.empty() || target.empty() || exe.empty() || (mode != L"setup" && mode != L"portable")) {
    writeResult(result, "heap-updater was started without what it needs");
    return 2;
  }

  waitForExit(static_cast<DWORD>(std::wcstoul(args[L"--pid"].c_str(), nullptr, 10)));
  const std::string error = mode == L"setup" ? installSetup(package) : installPortable(package, target);
  writeResult(result, error);
  relaunch(exe, target);
  return error.empty() ? 0 : 1;
}
