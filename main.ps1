# main.ps1
#requires -Version 5.1
param(
    [int]$diskNum
)
# Import module
Import-Module (Join-Path $PSScriptRoot "DiskTools.psm1") -Force #-Verbose

# Check and elevate immediately using the main script's path
Assert-Administrator -ScriptPath $PSCommandPath

# --- Rest of your script logic ---
Write-Host "Running as Administrator!" -ForegroundColor Green

Show-DiskSummaryByNumber -DiskNumber $diskNum

#Show-AllDiskSummary

