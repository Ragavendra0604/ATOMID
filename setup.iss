[Setup]
AppId={{ATOMID-STORE-APP-ID}}
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
UninstallDisplayIcon={app}\atomid.exe

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\atomid.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Atomid Store"; Filename: "{app}\atomid.exe"
Name: "{commondesktop}\Atomid Store"; Filename: "{app}\atomid.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\atomid.exe"; Description: "{cm:LaunchProgram,Atomid Store}"; Flags: nowait postinstall skipifsilent
