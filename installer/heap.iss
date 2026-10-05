; Inno Setup script for heap. — builds a Windows installer around the portable
; windeployqt bundle produced by the CMake `portable` target.
;
; Invoked from CI (see .github/workflows/release.yml) with:
;   ISCC /DAppVersion=<tag> /DBundleDir=<abs path to build\heap-portable> \
;        /F<output basename> installer\heap.iss
;
; AppVersion / BundleDir are required defines; sensible fallbacks let the
; script also be opened directly in the Inno Setup IDE for local testing.

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif
#ifndef BundleDir
  #define BundleDir "..\build\heap-portable"
#endif

[Setup]
AppId={{6F4C9E2A-3B7D-4E1F-9A6C-0D2B1E8F5A44}
AppName=heap.
AppVersion={#AppVersion}
AppPublisher=heap.
DefaultDirName={autopf}\heap
; Always ask where to install, also on an upgrade (prefilled with the folder
; of the previous install).
DisableDirPage=no
; "Install for all users" (Program Files, needs admin) stays the default;
; "only for me" installs anywhere without elevation. The in-app updater
; (APP-125) passes /ALLUSERS or /CURRENTUSER to stay in the mode the
; previous install used.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog commandline
DefaultGroupName=heap.
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\heap.exe
OutputDir={#SourcePath}\Output
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; Recursively pack the entire portable bundle (heap.exe + Qt runtime + QML).
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; The AppUserModelID is what Windows shows toasts under (APP-155); heap.exe
; sets the same one on its process (NotificationCenter_win.cpp).
Name: "{group}\heap."; Filename: "{app}\heap.exe"; AppUserModelID: "local.heap.app"
Name: "{group}\Uninstall heap."; Filename: "{uninstallexe}"
Name: "{autodesktop}\heap."; Filename: "{app}\heap.exe"; AppUserModelID: "local.heap.app"; Tasks: desktopicon

[Registry]
; heap:// — toast buttons start heap with a heap://notify URI (APP-155). heap
; also registers it per user at startup; this covers the first toast.
Root: HKA; Subkey: "Software\Classes\heap"; ValueType: string; ValueName: ""; ValueData: "URL:heap"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\heap"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\heap\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\heap.exe"" ""%1"""
; Start at login (APP-154) is written by heap itself; uninstalling removes it.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "heap"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\heap.exe"; Description: "Launch heap."; Flags: nowait postinstall skipifsilent
