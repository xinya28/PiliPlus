; Inno Setup script for the Windows ARM64 build of PiliPlus.
;
; This mirrors windows/packaging/exe/inno_setup.iss (the fastforge/x64 variant)
; but targets arm64 instead of x64. It is compiled directly with ISCC.exe, e.g.
;
;   ISCC.exe /DAppVersion=2.2.1+5655 ^
;            /DSourceDir=C:\src\PiliPlus\build\windows\arm64\runner\Release ^
;            /DOutputDir=C:\src\PiliPlus\dist ^
;            /DOutputBaseFilename=PiliPlus_windows_2.2.1+5655_arm64_setup ^
;            windows\packaging\exe\inno_setup_arm64.iss
;
; See .github/workflows/win_arm64.yml for the CI invocation.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#ifndef SourceDir
  #define SourceDir "..\..\..\build\windows\arm64\runner\Release"
#endif

#ifndef OutputDir
  #define OutputDir "."
#endif

#ifndef OutputBaseFilename
  #define OutputBaseFilename "PiliPlus_windows_arm64_setup"
#endif

#ifndef SetupIcon
  #define SetupIcon "..\..\runner\resources\app_icon.ico"
#endif

#define MyDisplayName "PiliPlus"
#define MyExecutableName "piliplus.exe"
#define MyPublisher "dom"
#define MyPublisherUrl "https://github.com/bggRGjQaUbCoE/PiliPlus"

[Setup]
; AppId is deliberately identical to the x64 installer so that an ARM64 install
; upgrades an existing (emulated) x64 install instead of creating a second app.
AppId={{5ef970f9-2b9e-4155-b7d6-a9d4dbd6b226}
AppVersion={#AppVersion}
AppName={#MyDisplayName}
AppPublisher={#MyPublisher}
AppPublisherURL={#MyPublisherUrl}
AppSupportURL={#MyPublisherUrl}
AppUpdatesURL={#MyPublisherUrl}
DefaultDirName={autopf}\{#MyDisplayName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma
SolidCompression=yes
SetupIconFile={#SetupIcon}
WizardStyle=modern
PrivilegesRequired=admin
; Windows 11 on ARM64 only: the payload is a native arm64 build.
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
UninstallDisplayIcon={app}\{#MyExecutableName}

[Code]
procedure KillOldProcess;
var ResultCode: Integer;
begin
  Exec('taskkill', '/F /IM {#MyExecutableName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function InitializeSetup(): Boolean;
begin
  KillOldProcess;
  Result := True;
end;

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "launchAtStartup"; Description: "{cm:AutoStartProgram,{#MyDisplayName}}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\{#MyDisplayName}"; Filename: "{app}\{#MyExecutableName}"
Name: "{autodesktop}\{#MyDisplayName}"; Filename: "{app}\{#MyExecutableName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyDisplayName}"; Filename: "{app}\{#MyExecutableName}"; WorkingDir: "{app}"; Tasks: launchAtStartup

[Registry]
Root: HKCU; Subkey: "Software\Classes\bilibili"; ValueType: string; ValueData: "URL:Bilibili Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\bilibili"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\bilibili\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyExecutableName},0"
Root: HKCU; Subkey: "Software\Classes\bilibili\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyExecutableName}"" ""%1"""

[Run]
Filename: "{app}\{#MyExecutableName}"; Description: "{cm:LaunchProgram,{#MyDisplayName}}"; Flags: runascurrentuser nowait postinstall skipifsilent
