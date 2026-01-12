param(
    [string]$Distro = "Ubuntu-24.04"
)

$ErrorActionPreference = "Stop"

# Partition = 0 → mount whole disk
$Disks = @(
    @{
        Path = "\\?\D:\VirtualMachines\vhds\Shared_v0.vhdx"
        Name = "vhd0"
        Type = "VHDX"
        Partition = 0
    },
    @{
        Path = "\\?\D:\VirtualMachines\vhds\Share1.vhdx"
        Name = "vhd1"
        Type = "VHDX"
        Partition = 0
    },
    @{
        Path = "\\.\PHYSICALDRIVE1"
        Name = "disk1_32g"
        Type = "PHYSICAL"
        Partition = 1
    },
    @{
        Path = "\\.\PHYSICALDRIVE2"
        Name = "disk2_110g"
        Type = "PHYSICAL"
        Partition = 1
    }
)

foreach ($disk in $Disks) {
    $path = $disk.Path
    $name = $disk.Name
    $type = $disk.Type
    $partition = $disk.Partition

    # NEW: naming rule
    if ($partition -eq 0) {
        $mountName = $name
    } else {
        $mountName = "${name}_p${partition}"
    }

    Write-Host "Detaching (if present): $path"
    wsl --unmount $path 2>$null

    Write-Host "Attaching $path as $mountName..."

    if ($partition -eq 0) {
        if ($type -eq "VHDX") {
            wsl --mount $path --vhd --name $mountName
        } else {
            wsl --mount $path --name $mountName
        }
    }
    else {
        wsl --mount $path --partition $partition --name $mountName
    }

    $cmd = "set -e; /usr/local/sbin/wsl-mount-disk.sh $mountName $type"
    Write-Host "Mounting inside WSL ($Distro): $mountName"
    wsl -d $Distro -- bash -c "`"$cmd`""
}

Write-Host ""
Write-Host ("All disks processed for {0}" -f $Distro)
foreach ($disk in $Disks) {
    if ($disk.Partition -eq 0) {
        $mountName = $disk.Name
    } else {
        $mountName = "$($disk.Name)_p$($disk.Partition)"
    }
    Write-Host ("  {0} -> /mnt/{1}" -f $disk.Path, $mountName)
}

Write-Host ("")
Write-Host ("")
Write-Host ("Use the following info to create and run Docker Container:")
Write-Host ("")
foreach ($disk in $Disks) {
    if ($disk.Partition -eq 0) {
        $mountName = $disk.Name
    } else {
        $mountName = "$($disk.Name)_p$($disk.Partition)"
    }
    Write-Host ("-v /mnt/wsl/{0}:/mnt/wsl/{0} \" -f $mountName)
}
Write-Host ("")
Write-Host ("")
Read-Host 'Press Enter to continue...'