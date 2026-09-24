# =====================================================================
# SmartPower Utility ERP - Automated Installer Build Script
# Architecture: Windows x64 (Native WebView2 GUI + Embedded PostgreSQL)
# =====================================================================

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "SmartPower ERP - Comprehensive Installer Build Pipeline" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$RootDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$FrontendDir = Join-Path $RootDir "frontend"
$ServerDir = Join-Path $RootDir "server"
$DistPortableDir = Join-Path $RootDir "dist_portable"
$RedistDir = Join-Path $RootDir "redist"
$IsccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

if (-not (Test-Path $IsccPath)) {
    $IsccPath = "C:\Program Files\Inno Setup 6\ISCC.exe"
}

if (-not (Test-Path $IsccPath)) {
    Write-Error "Inno Setup Compiler (ISCC.exe) not found!"
}

# 1. Verify Prerequisites in redist/
Write-Host ""
Write-Host "[1/4] Verifying prerequisites in $RedistDir..." -ForegroundColor Yellow
if (-not (Test-Path $RedistDir)) {
    New-Item -ItemType Directory -Force -Path $RedistDir | Out-Null
}

$vcRedist = Join-Path $RedistDir "VC_redist.x64.exe"
$wv2Setup = Join-Path $RedistDir "MicrosoftEdgeWebview2Setup.exe"

if (-not (Test-Path $vcRedist) -or (Get-Item $vcRedist).Length -lt 1000000) {
    Write-Host "Downloading Microsoft Visual C++ 2015-2022 Redistributable (x64)..." -ForegroundColor Magenta
    curl.exe -L -o $vcRedist "https://aka.ms/vs/17/release/vc_redist.x64.exe"
}

if (-not (Test-Path $wv2Setup) -or (Get-Item $wv2Setup).Length -lt 500000) {
    Write-Host "Downloading Microsoft Edge WebView2 Runtime Evergreen Bootstrapper..." -ForegroundColor Magenta
    curl.exe -L -o $wv2Setup "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
}

$vcLen = (Get-Item $vcRedist).Length
$wvLen = (Get-Item $wv2Setup).Length
Write-Host "Prerequisites verified: VC_redist.x64.exe ($vcLen bytes), MicrosoftEdgeWebview2Setup.exe ($wvLen bytes)" -ForegroundColor Green

# 2. Build & Sync Frontend Assets to Go Embedded Directory
Write-Host ""
Write-Host "[2/4] Building and Syncing Frontend SPA assets..." -ForegroundColor Yellow
if (Get-Command npm -ErrorAction SilentlyContinue) {
    Push-Location $FrontendDir
    try {
        Write-Host "Running frontend build (npm run build)..." -ForegroundColor Magenta
        npm run build
    } finally {
        Pop-Location
    }
}

$UiDistDir = Join-Path $ServerDir "internal\ui\dist"
if (Test-Path (Join-Path $FrontendDir "dist")) {
    if (Test-Path $UiDistDir) {
        Remove-Item -Path (Join-Path $UiDistDir "*") -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory -Force -Path $UiDistDir | Out-Null
    }
    Copy-Item -Path (Join-Path $FrontendDir "dist\*") -Destination $UiDistDir -Recurse -Force
    Write-Host "Frontend assets synced to $UiDistDir" -ForegroundColor Green
} else {
    Write-Host "frontend/dist not found, using existing embedded assets." -ForegroundColor DarkYellow
}

# 3. Compile Go Standalone Monolith (Hidden Console GUI)
Write-Host ""
Write-Host "[3/4] Compiling Go standalone executable (SmartPowerERP.exe)..." -ForegroundColor Yellow
Push-Location $ServerDir
try {
    $env:CGO_ENABLED = "0"
    $env:GOOS = "windows"
    $env:GOARCH = "amd64"
    go build -ldflags "-s -w -H=windowsgui" -o (Join-Path $DistPortableDir "SmartPowerERP.exe") ./cmd/server
    $exeLen = (Get-Item (Join-Path $DistPortableDir "SmartPowerERP.exe")).Length
    Write-Host "Compiled SmartPowerERP.exe successfully ($exeLen bytes)" -ForegroundColor Green

    Write-Host "Compiling native updater helper (updater.exe)..." -ForegroundColor Magenta
    go build -ldflags "-s -w -H=windowsgui" -o (Join-Path $DistPortableDir "updater.exe") ./cmd/updater
    $updLen = (Get-Item (Join-Path $DistPortableDir "updater.exe")).Length
    Write-Host "Compiled updater.exe successfully ($updLen bytes)" -ForegroundColor Green
} finally {
    Pop-Location
}

# 4. Compile Inno Setup Script
Write-Host ""
Write-Host "[4/4] Compiling Inno Setup Standalone Installer..." -ForegroundColor Yellow
Push-Location $RootDir
try {
    $issFile = Join-Path $RootDir "SmartPower_Go_Setup.iss"
    & $IsccPath $issFile
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Inno Setup compilation failed with code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$setupExe = Join-Path $RootDir "Setup.exe"
if (Test-Path $setupExe) {
    $sizeMB = [math]::Round((Get-Item $setupExe).Length / 1MB, 2)
    
    # Copy to target distribution names and folders
    $v100Exe = Join-Path $RootDir "SmartPowerERP_Setup_v1.0.0.exe"
    Copy-Item -Path $setupExe -Destination $v100Exe -Force
    
    $bundleDirs = Get-ChildItem -Path $RootDir -Directory | Where-Object { $_.Name -match "[^\x00-\x7F]" -or $_.Name -like "*Final*" -or $_.Name -like "*Bundle*" }
    foreach ($bDir in $bundleDirs) {
        $finalExe = Join-Path $bDir.FullName "SmartPowerERP_Setup.exe"
        Copy-Item -Path $setupExe -Destination $finalExe -Force
        Write-Host "Synchronized to: $finalExe" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "SUCCESS: Setup.exe built and synchronized successfully!" -ForegroundColor Green
    Write-Host "Path: $setupExe" -ForegroundColor Green
    Write-Host "Versioned: $v100Exe" -ForegroundColor Green
    Write-Host "Size: $sizeMB MB" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
} else {
    Write-Error "Setup.exe was not created."
}
