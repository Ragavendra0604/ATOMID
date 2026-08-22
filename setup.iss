; Inno Setup script for the Atomid Store desktop build.
;
; Build the app first, then compile this:
;   flutter build windows --release
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" setup.iss
;
; The installer lands in build\windows\installer\AtomidSetup.exe

#define AppExeName "atomid.exe"
#define ReleaseDir "build\windows\x64\runner\Release"

; Visual C++ runtime, shipped next to the exe.
;
; atomid.exe imports MSVCP140.dll, VCRUNTIME140.dll and VCRUNTIME140_1.dll,
; and Flutter does not copy them into the Release folder. A PC that has never
; had the VC++ Redistributable installed shows "the code execution cannot
; proceed because VCRUNTIME140.dll was not found" and the app never opens —
; which looks like a broken build rather than a missing system component.
;
; App-local deployment is permitted by the Visual Studio redistributable
; licence and avoids making every user run a separate installer first.
;
; The path below is one machine's; it embeds the Visual Studio edition
; (BuildTools vs Community) and an exact toolset version, so it is wrong on
; most other machines and goes stale on the next VS update. The compile fails
; loudly when it is wrong rather than producing an installer quietly missing
; the runtime — but rather than editing this file each time, override it:
;
;   ISCC /DCrtDir="<path>" setup.iss
;
; To find the path on a given machine:
;
;   dir /s /b "C:\Program Files*\Microsoft Visual Studio\*\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT"
;
; If that returns nothing, the "Desktop development with C++" workload is not
; installed — which also means `flutter build windows` cannot have produced
; the Release folder this script packages.
#ifndef CrtDir
  #define CrtDir "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Redist\MSVC\14.51.36231\x64\Microsoft.VC145.CRT"
#endif

[Setup]
; Permanent. Windows identifies the app by this for upgrade and uninstall, so
; changing it after a release makes the next version install alongside the old
; one instead of replacing it, leaving two entries in Add/Remove Programs.
AppId={{1B5371F5-C6DE-47B2-8D82-3CB265F50D07}
AppName=Atomid Store
AppVersion=1.0.0
AppPublisher=Atomid
DefaultDirName={autopf}\Atomid Store
DefaultGroupName=Atomid Store
OutputDir=build\windows\installer
OutputBaseFilename=AtomidSetup
Compression=lzma2/ultra64
SolidCompression=yes
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
WizardStyle=modern

; Without these, {autopf} resolves to "Program Files (x86)" on 64-bit Windows
; and a 64-bit app is installed into the 32-bit program folder.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Listed explicitly rather than globbing the whole Release folder. That folder
; also holds link-time artefacts (.lib, .exp), build metadata and — if the
; MSIX packager has ever been run — a complete .msix installer. Copying "*"
; put roughly 70 MB of files into the installer that the app never loads,
; including a second installer nested inside this one.
Source: "{#ReleaseDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

Source: "{#CrtDir}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#CrtDir}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#CrtDir}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Atomid Store"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall Atomid Store"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Atomid Store"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,Atomid Store}"; Flags: nowait postinstall skipifsilent
