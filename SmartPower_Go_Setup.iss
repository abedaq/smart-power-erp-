; =====================================================================
; SmartPower Utility ERP - Professional Inno Setup Script
; Architecture: Windows x64 (Native WebView2 GUI + Embedded PostgreSQL)
; Complete Offline / Clean Windows 7/8/10/11 Self-Contained Installer
; =====================================================================

#define MyAppName "Smart Power ERP"
#define MyAppVersion "3.4.3.9"
#define MyAppPublisher "SmartPower Technologies"
#define MyAppExeName "SmartPowerERP.exe"

[Setup]
AppId={{D8A1B7C3-9F24-4E88-A63E-5B1D0E47F9A2}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Smart Power ERP
DefaultGroupName={#MyAppName}
OutputDir=.\
OutputBaseFilename=Setup
SetupIconFile=icon.ico
UninstallDisplayIcon={app}\icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
DirExistsWarning=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=no
RestartApplications=no
UsePreviousAppDir=yes

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; ---------------------------------------------------------------------
; 1. Prerequisites (Extracted to temporary directory during setup)
; ---------------------------------------------------------------------
Source: "redist\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall ignoreversion
Source: "redist\MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall ignoreversion

; ---------------------------------------------------------------------
; 2. Main Executable, Updater and Application Icons
; ---------------------------------------------------------------------
Source: "dist_portable\SmartPowerERP.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist_portable\updater.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "icon.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "icon.png"; DestDir: "{app}"; Flags: ignoreversion

; ---------------------------------------------------------------------
; 3. Embedded Portable PostgreSQL Engine & Visual C++ Runtime DLLs
; ---------------------------------------------------------------------
Source: "dist_portable\pgsql\*"; DestDir: "{app}\pgsql"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "dist_portable\*.dll"; DestDir: "{app}"; Flags: ignoreversion

; ---------------------------------------------------------------------
; 4. Instant Database Cluster Template (Zero-initdb startup)
; ---------------------------------------------------------------------
Source: "dist_portable\data_template\*"; DestDir: "{app}\data_template"; Flags: ignoreversion recursesubdirs createallsubdirs

; ---------------------------------------------------------------------
; 5. Database Schema & Assets
; ---------------------------------------------------------------------
Source: "dist_portable\schema\*"; DestDir: "{app}\schema"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "dist_portable\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\icon.ico"
Name: "{autoprograms}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon; IconFilename: "{app}\icon.ico"

[Run]
; ---------------------------------------------------------------------
; A. Install Visual C++ 2015-2022 x64 Redistributable silently if missing
; ---------------------------------------------------------------------
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Check: NeedInstallVCRedist; StatusMsg: "جاري تثبيت مكتبات مايكروسوفت الأساسية (Visual C++ 2015-2022)..."; Flags: runhidden

; ---------------------------------------------------------------------
; B. Install Microsoft Edge WebView2 Runtime silently if missing
; ---------------------------------------------------------------------
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; Check: NeedInstallWebView2; StatusMsg: "جاري تثبيت مشغل واجهات مايكروسوفت (Microsoft Edge WebView2 Runtime)..."; Flags: runhidden

; ---------------------------------------------------------------------
; C. Launch Application post-installation
; ---------------------------------------------------------------------
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Delete application binaries on uninstall, but PRESERVE customer database data and backups in %LOCALAPPDATA%
Type: filesandordirs; Name: "{app}"

[Code]
// ---------------------------------------------------------------------
// Check if Microsoft Edge WebView2 Runtime is installed on the machine
// ---------------------------------------------------------------------
function CheckWebView2Branch(RootKey: Integer; SubKeyName: String): Boolean;
var
  Version: String;
begin
  Result := False;
  if RegQueryStringValue(RootKey, SubKeyName, 'pv', Version) then
  begin
    if (Trim(Version) <> '') and (Trim(Version) <> '0.0.0.0') then
      Result := True;
  end;
end;

function IsWebView2Installed(): Boolean;
begin
  Result := CheckWebView2Branch(HKLM64, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
            CheckWebView2Branch(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
            CheckWebView2Branch(HKLM64, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
            CheckWebView2Branch(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
            CheckWebView2Branch(HKCU, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}');
end;

function NeedInstallWebView2(): Boolean;
begin
  Result := not IsWebView2Installed();
end;

// ---------------------------------------------------------------------
// Check if Visual C++ 2015-2022 (x64) Redistributable is installed
// ---------------------------------------------------------------------
function CheckVCRedistBranch(RootKey: Integer; SubKeyName: String): Boolean;
var
  InstalledVal: Cardinal;
begin
  Result := False;
  if RegQueryDWordValue(RootKey, SubKeyName, 'Installed', InstalledVal) then
  begin
    if InstalledVal = 1 then
      Result := True;
  end;
end;

function IsVCRedistInstalled(): Boolean;
begin
  Result := CheckVCRedistBranch(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64') or
            CheckVCRedistBranch(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64') or
            CheckVCRedistBranch(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64') or
            CheckVCRedistBranch(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64') or
            CheckVCRedistBranch(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X64');
end;

function NeedInstallVCRedist(): Boolean;
begin
  Result := not IsVCRedistInstalled();
end;

// ---------------------------------------------------------------------
// Safe process termination and legacy shortcuts cleanup
// ---------------------------------------------------------------------
procedure CleanLegacyShortcuts();
var
  OldPath: String;
begin
  // Remove common legacy desktop shortcuts (from previous Program Files installation)
  OldPath := ExpandConstant('{commondesktop}\{#MyAppName}.lnk');
  if FileExists(OldPath) then DeleteFile(OldPath);

  OldPath := ExpandConstant('{commonprograms}\{#MyAppName}.lnk');
  if FileExists(OldPath) then DeleteFile(OldPath);

  OldPath := ExpandConstant('{userdesktop}\{#MyAppName}.lnk');
  if FileExists(OldPath) then DeleteFile(OldPath);

  OldPath := ExpandConstant('{userprograms}\{#MyAppName}.lnk');
  if FileExists(OldPath) then DeleteFile(OldPath);
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('taskkill.exe', '/F /IM SmartPowerERP.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill.exe', '/F /IM updater.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill.exe', '/F /IM postgres.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
  CleanLegacyShortcuts();
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    CleanLegacyShortcuts();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    Exec('taskkill.exe', '/F /IM SmartPowerERP.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('taskkill.exe', '/F /IM updater.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('taskkill.exe', '/F /IM postgres.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(500);
    CleanLegacyShortcuts();
  end
  else if CurUninstallStep = usPostUninstall then
  begin
    DelTree(ExpandConstant('{app}'), True, True, True);
  end;
end;
