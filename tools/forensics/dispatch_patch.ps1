<#
.SYNOPSIS
    SmartPower ERP - Developer Signed Command & Patch Dispatcher
.DESCRIPTION
    Signs an SQL patch (or a force backup request) using the developer Ed25519 private key
    and uploads the command to Supabase targeted at a specific station HWID.
.EXAMPLE
    # 1. Trigger remote backup
    .\dispatch_patch.ps1 -TargetHWID "8167D024A9B1C2D3" -ForceBackup

    # 2. Send signed SQL patch (Transactional)
    .\dispatch_patch.ps1 -TargetHWID "8167D024A9B1C2D3" -SqlFile "fix_customer_105.sql"

    # 3. Send non-transactional maintenance command
    .\dispatch_patch.ps1 -TargetHWID "8167D024A9B1C2D3" -SqlFile "reindex.sql" -DirectMode
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$TargetHWID,

    [string]$SqlFile = "",
    [switch]$ForceBackup,
    [switch]$DirectMode,
    [string]$MinAppVersion = "1.0.0",
    [string]$MaxAppVersion = "",
    [int]$TTLHours = 48,
    [string]$SupabaseURL = "https://pkuoytiickgbtfeffmxq.supabase.co",
    [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrdW95dGlpY2tnYnRmZWZmbXhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0NDk0MjAsImV4cCI6MjEwNDAyNTQyMH0.9aGjAHdibP2uKiiTQ8XuGsYmwsZeWsA3hVQ9gD4xq7Q"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🛡️ SmartPower ERP - Signed Patch & Command Dispatcher" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$serverDir = Resolve-Path (Join-Path $PSScriptRoot "..\..\server")

# Resolve Private Key
$privKeyPath = Join-Path $PSScriptRoot "keys\developer_private.key"
if (-not (Test-Path $privKeyPath)) {
    Write-Error "Developer private key not found at '$privKeyPath'. Run 'patch_signer gen-keys' first."
    exit 1
}

$cmdType = "RUN_SQL_PATCH"
$tempSqlFile = ""
$isTransactional = -not $DirectMode

if ($ForceBackup) {
    $cmdType = "FORCE_BACKUP"
    # Create empty payload file for signing
    $tempSqlFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tempSqlFile -Value "-- FORCE_BACKUP_TRIGGER --"
    $SqlFile = $tempSqlFile
} else {
    if ($SqlFile -eq "" -or (-not (Test-Path $SqlFile))) {
        Write-Error "Please specify a valid -SqlFile path or use -ForceBackup."
        exit 1
    }
}

$tempJsonOut = [System.IO.Path]::GetTempFileName()

try {
    Write-Host "🔏 Signing command payload with Ed25519 private key..." -ForegroundColor Cyan

    $signerArgs = @(
        "run", "./cmd/patch_signer/main.go", "sign",
        "-sql", (Resolve-Path $SqlFile),
        "-hwid", $TargetHWID,
        "-type", $cmdType,
        "-key", (Resolve-Path $privKeyPath),
        "-min-ver", $MinAppVersion,
        "-ttl", $TTLHours.ToString(),
        "-transactional", ($isTransactional.ToString().ToLower()),
        "-out", $tempJsonOut
    )

    if ($MaxAppVersion -ne "") {
        $signerArgs += "-max-ver"
        $signerArgs += $MaxAppVersion
    }

    $signProcess = Start-Process -FilePath "go" -ArgumentList $signerArgs -WorkingDirectory $serverDir -NoNewWindow -Wait -PassThru
    if ($signProcess.ExitCode -ne 0) {
        Write-Error "Signer failed with exit code $($signProcess.ExitCode)"
        exit 1
    }

    if (-not (Test-Path $tempJsonOut)) {
        Write-Error "Signed JSON output file was not generated."
        exit 1
    }

    $commandJson = Get-Content -Path $tempJsonOut -Raw

    # Upload command to Supabase REST API
    Write-Host "☁️ Uploading signed command to Supabase for station '$TargetHWID'..." -ForegroundColor Cyan

    $headers = @{
        "apikey"        = $AnonKey
        "Authorization" = "Bearer $AnonKey"
        "Content-Type"  = "application/json"
        "Prefer"        = "return=representation"
    }

    $apiURL = "$SupabaseURL/rest/v1/station_remote_commands"
    $result = Invoke-RestMethod -Uri $apiURL -Headers $headers -Method Post -Body $commandJson

    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "✅ Command successfully registered in Supabase!" -ForegroundColor Green
    if ($result) {
        Write-Host "   Command ID : $($result[0].id)"
        Write-Host "   Status     : $($result[0].status)"
        Write-Host "   Target HWID: $($result[0].target_hwid)"
        Write-Host "   Command    : $($result[0].command_type)"
        Write-Host "   Expires At : $($result[0].expires_at)"
    }
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "The station will automatically claim and execute this command within 60 seconds of being online."

} finally {
    if ($tempJsonOut -and (Test-Path $tempJsonOut)) {
        Remove-Item $tempJsonOut -Force
    }
    if ($tempSqlFile -and (Test-Path $tempSqlFile)) {
        Remove-Item $tempSqlFile -Force
    }
}
