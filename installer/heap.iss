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
Name: "{group}\heap."; Filename: "{app}\heap.exe"
Name: "{group}\Uninstall heap."; Filename: "{uninstallexe}"
Name: "{autodesktop}\heap."; Filename: "{app}\heap.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\heap.exe"; Description: "Launch heap."; Flags: nowait postinstall skipifsilent
