$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "`"$PSCommandPath`""
    exit
}

Write-Host "Running as admin now."



# MountDisksIntoWsl2.ps1
# Entry point to run both scripts in order

Write-Host "=== MountDisksIntoWsl2.ps1 starting ==="
Set-Location $PSScriptRoot
$root = $PSScriptRoot

$gen = Join-Path $root "generate-runtime.ps1"
$proc = Join-Path $root "process-runtime.ps1"

# --- Check existence ---
if (-not (Test-Path $gen)) {
    throw "generate-runtime.ps1 not found in: $root"
}

if (-not (Test-Path $proc)) {
    throw "process-runtime.ps1 not found in: $root"
}
wsl --shutdown
# --- Run generate-runtime.ps1 ---
Write-Host ""
Write-Host "Running generate-runtime.ps1..."

& $gen

#if ($LASTEXITCODE -ne 0) {
#    throw "generate-runtime.ps1 failed with exit code $LASTEXITCODE"
#}
Write-Warning "generate-runtime.ps1 exited with code $LASTEXITCODE"

# --- Run process-runtime.ps1 ---
Write-Host ""
Write-Host "Running process-runtime.ps1..."
& $proc

if ($LASTEXITCODE -ne 0) {
    throw "process-runtime.ps1 failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "=== MountDisksIntoWsl2.ps1 completed successfully ==="

wsl.exe --cd ~