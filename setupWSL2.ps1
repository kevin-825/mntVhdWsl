# ============================================================
# setup.ps1
# Entry point to run all WSL2 disk‑mount pipeline scripts
# ============================================================
param(
    [switch]$genf
)

Write-Host "genf value = $genf"


#include other script
# 1. Dot source compare.ps1 to load its functions into memory
. "$PSScriptRoot\compare.ps1"

# --- Helper Functions ---
function Test-FileEmpty {
    param ([string]$Path)
    # Returns true if file does not exist OR is 0 bytes
    if (-not (Test-Path $Path)) { return $true }
    if ((Get-Item $Path).Length -eq 0) { return $true }
    return $false
}

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

# --- Paths & Configuration ---
Set-Location $PSScriptRoot
$root        = $PSScriptRoot
$devicesJson = Join-Path $root "devices.json"

$genConfig   = Join-Path $root "configure.ps1"
$genRuntime  = Join-Path $root "generate-runtime.ps1"
$procRuntime = Join-Path $root "process-runtime.ps1"

# --- Reset WSL state ---
Write-Host "Shutting down WSL..."
wsl --shutdown
Start-Sleep -Seconds 1

# ------------------------------------------------------------
# 1. configure.ps1 (Conditional Execution)
# ------------------------------------------------------------
if (Test-FileEmpty -Path $devicesJson) {
    Write-Host "devices.json is missing or empty. Running configure.ps1..." -ForegroundColor Cyan
    if (Test-Path $genConfig) {
        & $genConfig
        if ($LASTEXITCODE -ne 0) { throw "configure.ps1 failed." }
    } else {
        throw "Required script missing: $genConfig"
    }
} else {
    Write-Host "Valid devices.json found. Skipping configuration." -ForegroundColor Green
}

# ------------------------------------------------------------
# 2. generate-runtime.ps1
# ------------------------------------------------------------
Write-Host "`nRunning generate-runtime.ps1..."
if (Test-Path $genRuntime) {
    & $genRuntime
    if ($LASTEXITCODE -ne 0) { throw "generate-runtime.ps1 failed." }
}

# ------------------------------------------------------------
# 3. process-runtime.ps1
# ------------------------------------------------------------
Write-Host "`genf flag is $genf..."
Write-Host "`nRunning process-runtime.ps1..."
if (Test-Path $procRuntime) {
    & $procRuntime -genf:$genf
    if ($LASTEXITCODE -ne 0) { throw "process-runtime.ps1 failed." }
}

# --- Sync  geenarted .bash_aliases_1 files into each user of each distro---

$localFile  = ".\.bash_aliases_1"

# Get all installed distros
$distros = wsl.exe -l -q |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" } |
    ForEach-Object { $_ -replace '[^\x20-\x7E]', '' }

Write-Host "Found distros: $($distros -join ', ')"
foreach ($distro in $distros) {

    Write-Host "===$distro==="

    # Get Linux users (UID >= 1000)
    $passwd = wsl.exe -d $distro -- cat /etc/passwd
    #Write-Host "Contents of /etc/passwd: $($passwd -join "`n")"
    $users = $passwd |
    ForEach-Object { $_.Trim() } |
    Select-String "^[^:]+:[^:]*:[1-9][0-9]{3}:" |
    ForEach-Object { ($_ -split ":")[0] }

    
    Write-Host "Found users: $($users -join ', ')"

    foreach ($user in $users) {
        Write-Host "  -> Syncing for user: $user"

        $targetFile = "\\wsl$\$distro\home\$user\.bash_aliases_1"

        Sync-FileIfChanged_contentbased `
            -SourcePath $localFile `
            -TargetPath $targetFile
    }
}

Write-Host "`n=== setup.ps1 completed successfully ==="
pause "Press any key to exit..."
