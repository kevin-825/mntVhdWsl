# ============================================================
# setup.ps1
# Entry point to run all WSL2 disk‑mount pipeline scripts
# ============================================================

# --- Ensure running as Administrator ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "`"$PSCommandPath`""
    exit
}

Write-Host "Running as admin now."
Write-Host "=== setup.ps1 starting ==="
Write-Host ""

# --- Move to script directory ---
Set-Location $PSScriptRoot
$root = $PSScriptRoot

# --- Script paths ---
$genConfig   = Join-Path $root "configure.ps1"
$genRuntime  = Join-Path $root "generate-runtime.ps1"
$procRuntime = Join-Path $root "process-runtime.ps1"

# --- Check existence ---
if (-not (Test-Path $genConfig)) {
    throw "generateWsl2MountConfig.ps1 not found in: $root"
}
if (-not (Test-Path $genRuntime)) {
    throw "generate-runtime.ps1 not found in: $root"
}
if (-not (Test-Path $procRuntime)) {
    throw "process-runtime.ps1 not found in: $root"
}

# --- Reset WSL state ---
Write-Host "Shutting down WSL..."
wsl --shutdown
Start-Sleep -Seconds 1

# ------------------------------------------------------------
# 1. generateWsl2MountConfig.ps1
# ------------------------------------------------------------
Write-Host ""
Write-Host "Running generateWsl2MountConfig.ps1..."
& $genConfig

if ($LASTEXITCODE -ne 0) {
    throw "generateWsl2MountConfig.ps1 failed with exit code $LASTEXITCODE"
}

# ------------------------------------------------------------
# 2. generate-runtime.ps1
# ------------------------------------------------------------
Write-Host ""
Write-Host "Running generate-runtime.ps1..."
& $genRuntime

if ($LASTEXITCODE -ne 0) {
    throw "generate-runtime.ps1 failed with exit code $LASTEXITCODE"
}

# ------------------------------------------------------------
# 3. process-runtime.ps1
# ------------------------------------------------------------
Write-Host ""
Write-Host "Running process-runtime.ps1..."
& $procRuntime

if ($LASTEXITCODE -ne 0) {
    throw "process-runtime.ps1 failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "=== setup.ps1 completed successfully ==="
Write-Host ""

# --- Drop into WSL home directory ---
wsl.exe --cd ~