#ifndef RID
  #define RID "win-x64"
#endif
#ifndef Version
  #define Version "1.2.0-beta.3"
#endif
[Setup]
AppId={{761E2C57-FA95-4F8B-9F74-7D6A8E6DBD81}
AppName=Codex Ledger
AppVersion={#Version}
AppPublisher=Codex Ledger contributors
AppPublisherURL=https://zhangligong0826.github.io/codex-ledger/
DefaultDirName={localappdata}\Programs\Codex Ledger
DefaultGroupName=Codex Ledger
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
MinVersion=10.0.22000
OutputDir=..\dist
OutputBaseFilename=Codex-Ledger-{#Version}-Windows-{#RID}-Setup
SetupIconFile=Ledger.App\AppIcon.ico
UninstallDisplayIcon={app}\CodexLedger.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
#if RID == "win-arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
[Files]
Source: "..\dist\{#RID}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{userprograms}\Codex Ledger"; Filename: "{app}\CodexLedger.exe"
[Run]
Filename: "{app}\CodexLedger.exe"; Description: "Open Codex Ledger"; Flags: nowait postinstall skipifsilent
[UninstallDelete]
Type: files; Name: "{app}\*.tmp"
[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "CodexLedger"; Flags: dontcreatekey uninsdeletevalue
