# Get the directory of this script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Define the script paths
$WinPs1Script = Join-Path $ScriptDir 'mount_vhd_wsl_mount_only.ps1'

# Example usage (uncomment as needed)
# & $WinCmdScript 'ubuntu' 'E:\vms\vmbox\Shared0.vhd' 'E:\Hyper-V\vhds\Share1.vhdx'
# & $WinCmdScript 'Ubuntu-24.04' 'E:\VHDs\Shared_v0.vhdx'

# Run the PowerShell script with parameters
& $WinPs1Script -Distro 'Ubuntu-24.04' -VhdPaths 'D:\VirtualMachines\vhds\Shared_v0.vhdx', 'D:\VirtualMachines\vhds\Share1.vhdx'
# Optional pause (like `pause` in CMD)
#Read-Host 'Press Enter to continue...'
Read-Host 'Press Enter to continue...'

