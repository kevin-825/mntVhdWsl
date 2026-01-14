# Get the directory of this script
# Get the directory of this script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Define the script paths


$WinPs1Script = Join-Path $ScriptDir 'mount_vhd_wsl_mount_only.ps1'
$MntPhysicalDriveScript = Join-Path $ScriptDir 'mountPhysicalDrive.ps1'


& $WinPs1Script -Distro 'Ubuntu-24.04' -VhdPaths 'D:\VirtualMachines\vhds\Shared_v0.vhdx', 'D:\VirtualMachines\vhds\Share1.vhdx'
& $MntPhysicalDriveScript

Read-Host 'Press Enter to continue...'

