; Inno Setup script for lowkey (heap until 0.8.0) — builds a Windows installer
; around the portable windeployqt bundle produced by the CMake `portable` target.
;
; Invoked from CI (see .github/workflows/release.yml) with:
;   ISCC /DAppVersion=<tag> /DBundleDir=<abs path to build\heap-portable> \
;        /F<output basename> installer\lowkey.iss
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
; The same AppId heap used: installing lowkey over heap 0.7 is an upgrade of
; the same program (one entry in Apps & features, one uninstaller), not a
; second app beside it (APP-280).
AppId={{6F4C9E2A-3B7D-4E1F-9A6C-0D2B1E8F5A44}
AppName=lowkey
AppVersion={#AppVersion}
AppPublisher=lowkey
; A new install goes to …\lowkey. An upgrade keeps heap's folder (the
; previous install's), so nothing that points into it breaks.
DefaultDirName={autopf}\lowkey
; Always ask where to install, also on an upgrade (prefilled with the folder
; of the previous install).
DisableDirPage=no
; "Install for all users" (Program Files, needs admin) stays the default;
; "only for me" installs anywhere without elevation. The in-app updater
; (APP-125) passes /ALLUSERS or /CURRENTUSER to stay in the mode the
; previous install used.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog commandline
DefaultGroupName=lowkey
DisableProgramGroupPage=yes
SetupIconFile=..\design\brand-export\lowkey\lowkey.ico
UninstallDisplayIcon={app}\lowkey.exe
UninstallDisplayName=lowkey
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

[InstallDelete]
; heap 0.7's shortcuts: the program is lowkey now. heap.exe itself stays in
; the bundle as a launcher for anything else that still starts it.
Type: filesandordirs; Name: "{autoprograms}\heap."
Type: files; Name: "{autoprograms}\heap..lnk"
Type: files; Name: "{autodesktop}\heap..lnk"

[Files]
; Recursively pack the entire portable bundle (lowkey.exe + Qt runtime + QML,
; and the heap.exe launcher).
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; The AppUserModelID is what Windows shows toasts under (APP-155); lowkey.exe
; sets the same one on its process (NotificationCenter_win.cpp).
Name: "{group}\lowkey"; Filename: "{app}\lowkey.exe"; AppUserModelID: "local.lowkey.app"
Name: "{group}\Uninstall lowkey"; Filename: "{uninstallexe}"
Name: "{autodesktop}\lowkey"; Filename: "{app}\lowkey.exe"; AppUserModelID: "local.lowkey.app"; Tasks: desktopicon

[Registry]
; lowkey:// — toast buttons start lowkey with a lowkey://notify URI (APP-155).
; lowkey also registers it per user at startup; this covers the first toast.
Root: HKA; Subkey: "Software\Classes\lowkey"; ValueType: string; ValueName: ""; ValueData: "URL:lowkey"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\lowkey"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\lowkey\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\lowkey.exe"" ""%1"""
; heap:// — a toast heap 0.7 showed may still sit in the Action Center.
Root: HKA; Subkey: "Software\Classes\heap"; ValueType: string; ValueName: ""; ValueData: "URL:heap"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\heap"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\heap\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\lowkey.exe"" ""%1"""
; Start at login (APP-154) is written by lowkey itself (it adopts heap 0.7's
; entry on its first start); uninstalling removes either.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "lowkey"; Flags: uninsdeletevalue dontcreatekey
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "heap"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\lowkey.exe"; Description: "Launch lowkey"; Flags: nowait postinstall skipifsilent
