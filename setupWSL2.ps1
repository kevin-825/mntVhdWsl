# ============================================================
# setup.ps1
# Entry point to run all WSL2 disk‑mount pipeline scripts
#Example:
# .\setupWSL2.ps1 -genf
# .\setupWSL2.ps1 -genf:$true
# Or to keep it false:
# .\setupWSL2.ps1
# .\setupWSL2.ps1 -genf:$false
# ============================================================
param(
    [switch]$genf,
    [switch]$f
)

Write-Host "genf value = $genf  f:$f"


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

function Invoke-Wsl {
    param([string]$Command)
    return (& wsl.exe bash -lc "$Command" 2>$null) -join "`n"
}

# --- Ensure running as Administrator ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    $elevatedArgs = "`"$PSCommandPath`""
    if ($genf) {
        $elevatedArgs += " -genf"
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $elevatedArgs
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
#wsl --shutdown
Start-Sleep -Seconds 1

# ------------------------------------------------------------
# 1. configure.ps1 (Conditional Execution)
# ------------------------------------------------------------
if ((Test-FileEmpty -Path $devicesJson) -or $f ) {
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
    try {
        # Run the PowerShell script
        & $genRuntime
        
        # Check $? instead of $LASTEXITCODE for PowerShell scripts
        if (-not $?) { 
            throw "generate-runtime.ps1 failed." 
        }
    } catch {
        Write-Host "`n[ERROR] ========================================" -ForegroundColor Red
        Write-Warning "Failed script   : $genRuntime"
        Write-Warning "Line number     : $($_.InvocationInfo.ScriptLineNumber)"
        Write-Warning "Error message   : $_"
        Write-Host "================================================" -ForegroundColor Red
        exit 1
    }
}

# ------------------------------------------------------------
# 3. process-runtime.ps1
# ------------------------------------------------------------
Write-Host "`genf flag is $genf..."
Write-Host "`nRunning process-runtime.ps1..."
if (Test-Path $procRuntime) {
    try {
        # Run the PowerShell script
        & $procRuntime -genf:$genf
        
        # Check $? instead of $LASTEXITCODE for PowerShell scripts
        if (-not $?) { 
            throw "generate-runtime.ps1 failed." 
        }
    } catch {
        Write-Host "`n[ERROR] ========================================" -ForegroundColor Red
        Write-Warning "Failed script   : $procRuntime"
        Write-Warning "Line number     : $($_.InvocationInfo.ScriptLineNumber)"
        Write-Warning "Error message   : $_"
        Write-Host "================================================" -ForegroundColor Red
        exit 1
    }
}

# --- Sync  geenarted .bash_aliases_1 files into each user of each distro---

$localFile  = ".\.bash_aliases_1"


$targetFile1 = "\\wsl$\Ubuntu\home\kevin\.bash_aliases_1"

Sync-FileIfChanged_contentbased -SourcePath $localFile -TargetPath $targetFile1

$winPath = $PWD.ProviderPath -replace '\\', '/'
$wslPathRaw = wsl.exe wslpath -u "$winPath" 2>&1
$wslProjectDir = $wslPathRaw.Trim()
$wslUser = (wsl whoami).Trim()
wsl.exe -u root bash -lc "cd '$wslProjectDir' && ./scripts/last_step.sh $wslUser"
Write-Host "`n=== setup.ps1 completed successfully ==="
wsl.exe --cd ~
