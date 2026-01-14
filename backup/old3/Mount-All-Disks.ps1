
param(
    [string]$Distro = "Ubuntu-24.04"
)


$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "`"$PSCommandPath`""
    exit
}

Write-Host "Running as admin now."


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
    },
    @{
        Path = "\\.\PHYSICALDRIVE5"
        Name = "ramdisk0"
        Type = "PHYSICAL"
        Partition = 1
    }
)

foreach ($disk in $Disks) {

    $path = $disk.Path
    $name = $disk.Name
    $type = $disk.Type
    $partition = $disk.Partition

    Write-Host "Processing $path ($type)"

    if ($type -eq "PHYSICAL") {

        if ($path -match "PHYSICALDRIVE(\d+)") {
            $diskNumber = [int]$matches[1]
            Write-Host "  Extracted disk number: $diskNumber"
        } else {
            Write-Host "  ERROR: Could not extract disk number from $path"
            continue
        }

        Write-Host "  Taking disk $diskNumber offline..."

        try {
            Set-Disk -Number $diskNumber -IsOffline $true -ErrorAction Stop
            Write-Host "  Disk $diskNumber is now offline."
        }
        catch {
            Write-Host "  Failed to offline disk ${diskNumber}: $($_)"
            continue
        }
    }
}


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

wsl /home/kflyn/wsl-mount-ramdisk.sh

wsl.exe -d $Distro --cd ~