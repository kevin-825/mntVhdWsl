param(
    [string]$Distro = "Ubuntu-24.04"
)

$ErrorActionPreference = "Stop"

# Must match Mount-All-Disks.ps1
$Disks = @(
    @{
        Path = "\\?\D:\VirtualMachines\vhds\Shared_v0.vhdx"
        Name = "vhd0"
    },
    @{
        Path = "\\?\D:\VirtualMachines\vhds\Share1.vhdx"
        Name = "vhd1"
    },
    @{
        Path = "\\.\PHYSICALDRIVE1"
        Name = "disk1_32g"
    },
    @{
        Path = "\\.\PHYSICALDRIVE2"
        Name = "disk2_110g"
    }
)

Write-Host "=== Cleaning up mounts inside WSL ($Distro) ==="

foreach ($disk in $Disks) {
    $name = $disk.Name
    $cmd  = "set -e; /usr/local/sbin/wsl-unmount-disk.sh $name"

    Write-Host "Cleaning up '$name' inside WSL..."
    wsl -d $Distro -- bash -c "`"$cmd`""
}

Write-Host "=== Detaching disks from WSL ==="

foreach ($disk in $Disks) {
    $path = $disk.Path
    Write-Host "Detaching $path..."
    wsl --unmount $path 2>$null
}

Write-Host "✅ All disks unmounted and detached."