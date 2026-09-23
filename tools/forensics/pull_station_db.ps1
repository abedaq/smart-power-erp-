<#
.SYNOPSIS
    SmartPower ERP - Developer Forensics DB Pull & Restore Tool
.DESCRIPTION
    Lists backups from Supabase, downloads the chosen station database backup (.sql.gz),
    verifies SHA256 integrity, decompresses it to .sql, and optionally restores it into
    a local test PostgreSQL database (smartpower_debug_db).
.EXAMPLE
    .\pull_station_db.ps1 -ListOnly
    .\pull_station_db.ps1 -Latest -AutoRestore
    .\pull_station_db.ps1 -ReferenceID "BAK-8167D024-20260923_103000" -AutoRestore
#>

param (
    [string]$ReferenceID = "",
    [switch]$Latest,
    [switch]$ListOnly,
    [switch]$AutoRestore,
    [string]$TargetDatabase = "smartpower_debug_db",
    [string]$TargetPort = "15432",
    [string]$SupabaseURL = "https://pkuoytiickgbtfeffmxq.supabase.co",
    [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrdW95dGlpY2tnYnRmZWZmbXhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0NDk0MjAsImV4cCI6MjEwNDAyNTQyMH0.9aGjAHdibP2uKiiTQ8XuGsYmwsZeWsA3hVQ9gD4xq7Q"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🔍 SmartPower ERP - Forensic Database Pull & Inspection" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Fetch available backups from Supabase
$headers = @{
    "apikey"        = $AnonKey
    "Authorization" = "Bearer $AnonKey"
    "Content-Type"  = "application/json"
}

$queryURL = "$SupabaseURL/rest/v1/station_database_backups?select=*&order=created_at.desc&limit=20"
try {
    $response = Invoke-RestMethod -Uri $queryURL -Headers $headers -Method Get
} catch {
    Write-Error "Failed to fetch backups from Supabase: $_"
    exit 1
}

if (-not $response -or $response.Count -eq 0) {
    Write-Host "ℹ️ No station database backups found in Supabase yet." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n📋 Recent Backups in Supabase:" -ForegroundColor Green
$idx = 1
foreach ($b in $response) {
    $sizeMB = [math]::Round($b.file_size_bytes / 1MB, 2)
    Write-Host " [$idx] Ref: $($b.reference_id) | Station: $($b.station_name) | HWID: $($b.hwid.Substring(0,[math]::Min(8, $b.hwid.Length))) | Size: ${sizeMB}MB | Customers: $($b.customer_count) | Date: $($b.created_at)"
    $idx++
}

if ($ListOnly) {
    exit 0
}

# 2. Select target backup
$target = $null
if ($ReferenceID -ne "") {
    $target = $response | Where-Object { $_.reference_id -eq $ReferenceID } | Select-Object -First 1
    if (-not $target) {
        Write-Error "Backup with Reference ID '$ReferenceID' not found."
        exit 1
    }
} elseif ($Latest) {
    $target = $response[0]
} else {
    $selection = Read-Host "`nEnter backup number to download (1-$($response.Count)) or 'L' for Latest"
    if ($selection -eq 'L' -or $selection -eq 'l' -or $selection -eq '') {
        $target = $response[0]
    } else {
        $selIdx = [int]$selection - 1
        if ($selIdx -ge 0 -and $selIdx -lt $response.Count) {
            $target = $response[$selIdx]
        } else {
            Write-Error "Invalid selection."
            exit 1
        }
    }
}

Write-Host "`n🎯 Selected Backup: $($target.reference_id)" -ForegroundColor Cyan
Write-Host "   File Name     : $($target.file_name)"
Write-Host "   Expected SHA256: $($target.sha256_hash)"
Write-Host "   Size (Bytes)  : $($target.file_size_bytes)"

# 3. Create download directory
$downloadDir = Join-Path $PSScriptRoot "downloads"
if (-not (Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
}

$gzFilePath = Join-Path $downloadDir $target.file_name
$sqlFilePath = $gzFilePath -replace '\.gz$', ''

# 4. Download file
Write-Host "`n⬇️ Downloading backup from Supabase Storage..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $target.file_url -OutFile $gzFilePath
    Write-Host "✅ Download complete: $gzFilePath" -ForegroundColor Green
} catch {
    Write-Error "Failed to download backup file: $_"
    exit 1
}

# 5. Verify SHA-256 Checksum
Write-Host "🔒 Verifying SHA-256 cryptographic integrity..." -ForegroundColor Cyan
$actualHash = (Get-FileHash -Path $gzFilePath -Algorithm SHA256).Hash.ToLower()
$expectedHash = $target.sha256_hash.ToLower()

if ($actualHash -ne $expectedHash) {
    Write-Host "❌ INTEGRITY ERROR: SHA256 mismatch!" -ForegroundColor Red
    Write-Host "   Expected: $expectedHash"
    Write-Host "   Actual  : $actualHash"
    Remove-Item $gzFilePath -Force
    exit 1
}
Write-Host "✅ SHA-256 verified! The backup file is 100% genuine and untampered." -ForegroundColor Green

# 6. Decompress .sql.gz
Write-Host "📦 Decompressing .sql.gz archive..." -ForegroundColor Cyan
$inFile = [System.IO.File]::OpenRead($gzFilePath)
$outFile = [System.IO.File]::Create($sqlFilePath)
$gzStream = New-Object System.IO.Compression.GZipStream($inFile, [System.IO.Compression.CompressionMode]::Decompress)

$buffer = New-Object byte[] 65536
while (($count = $gzStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
    $outFile.Write($buffer, 0, $count)
}
$gzStream.Close()
$outFile.Close()
$inFile.Close()

$sqlFileInfo = Get-Item $sqlFilePath
$sqlSizeMB = [math]::Round($sqlFileInfo.Length / 1MB, 2)
Write-Host "✅ Decompressed successfully to: $sqlFilePath (${sqlSizeMB} MB)" -ForegroundColor Green

# 7. Optional Automatic Database Restore
if ($AutoRestore) {
    Write-Host "`n🚀 Restoring into local test database '$TargetDatabase' on port $TargetPort..." -ForegroundColor Cyan

    # Locate psql.exe
    $psqlCandidates = @(
        "$PSScriptRoot\..\..\pgsql\bin\psql.exe",
        "$PSScriptRoot\..\..\dist_portable\pgsql\bin\psql.exe",
        "C:\Program Files\PostgreSQL\18\bin\psql.exe",
        "C:\Program Files\PostgreSQL\17\bin\psql.exe",
        "C:\Program Files\PostgreSQL\16\bin\psql.exe"
    )
    $psqlPath = ""
    foreach ($p in $psqlCandidates) {
        if (Test-Path $p) {
            $psqlPath = $p
            break
        }
    }

    if (-not $psqlPath) {
        Write-Host "⚠️ psql.exe not found automatically. You can manually restore $sqlFilePath into your database." -ForegroundColor Yellow
    } else {
        $env:PGPASSWORD = "postgres"
        # 7.1 Drop & Recreate debug database
        & $psqlPath -h 127.0.0.1 -p $TargetPort -U postgres -d postgres -c "DROP DATABASE IF EXISTS $TargetDatabase;" 2>$null
        & $psqlPath -h 127.0.0.1 -p $TargetPort -U postgres -d postgres -c "CREATE DATABASE $TargetDatabase;"
        
        # 7.2 Import SQL dump
        Write-Host "⏳ Importing SQL dump..." -ForegroundColor Cyan
        & $psqlPath -h 127.0.0.1 -p $TargetPort -U postgres -d $TargetDatabase -f $sqlFilePath

        Write-Host "==========================================================" -ForegroundColor Green
        Write-Host "🎉 Database restored successfully into '$TargetDatabase'!" -ForegroundColor Green
        Write-Host "   Connection: postgres://postgres:postgres@127.0.0.1:$TargetPort/$TargetDatabase"
        Write-Host "   You can now inspect it via pgAdmin, DBeaver, or VSCode."
        Write-Host "==========================================================" -ForegroundColor Green
    }
}
