<# 
FINAL generate-runtime.ps1 (with PartitionsNeedMount + PartitionMountLabel + MountRequired)
Option B: WSL mounts via \\.\PHYSICALDRIVE<N>

Input:  devices.json
Output: runtime-devices.json

devices.json schema (per device):

{
  "Path": "\\\\.\\PHYSICALDRIVE5" or "\\\\?\\D:\\VirtualMachines\\vhds\\vhd2.vhdx",
  "DevType": "PhysicalRamDisk" | "PhysicalHardDisk" | "VirtualVhdx",
  "MountLabel": "vhd2",
  "OpMode": "MountAllExt4",
  "PartitionsNeedMount": [1,2,3],   # list of partitions to mount
  "mountStatus": "unknown"          # informational only
}
#>

param(
    [string]$ConfigPath  = ".\devices.json",
    [string]$RuntimePath = ".\runtime-devices.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== generate-runtime.ps1 starting ==="

# -------------------------------
# Load config
# -------------------------------
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$configRoot = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$config    = $configRoot.Devices

if (-not $config) {
    throw "No devices found in $ConfigPath"
}

Write-Host "Loaded $($config.Count) devices."

# -------------------------------
# Phase 1 — Attach all VHDX (attach-only)
# -------------------------------
foreach ($dev in $config) {
    if ($dev.DevType -eq "VirtualVhdx") {

        # Normalize path for Mount-VHD / Get-VHD
        $vhdPath = $dev.Path
        if ($vhdPath -like "\\?\*") {
            $vhdPath = $vhdPath.Substring(4)
        }

        # Check if already attached
        $already = Get-VHD -Path $vhdPath -ErrorAction SilentlyContinue
        if ($already -and $already.Attached) {
            Write-Host "VHDX already attached: $vhdPath (DiskNumber=$($already.DiskNumber))"
            continue
        }

        Write-Host "Mount-VHD -Path '$vhdPath' -NoDriveLetter"
        Mount-VHD -Path $vhdPath -NoDriveLetter
    }
}

# -------------------------------
# Helper: resolve Disk object
# -------------------------------
function Resolve-Disk {
    param($dev)

    switch ($dev.DevType) {

        "VirtualVhdx" {
            $vhdPath = $dev.Path
            if ($vhdPath -like "\\?\*") {
                $vhdPath = $vhdPath.Substring(4)
            }
            $vhd = Get-VHD -Path $vhdPath
            return Get-Disk -Number $vhd.DiskNumber
        }

        "PhysicalHardDisk" {
            if ($dev.Path -match "PHYSICALDRIVE(\d+)") {
                return Get-Disk -Number $Matches[1]
            }
            throw "Invalid PhysicalHardDisk Path: $($dev.Path)"
        }

        "PhysicalRamDisk" {
            if ($dev.Path -match "PHYSICALDRIVE(\d+)") {
                return Get-Disk -Number $Matches[1]
            }
            throw "Invalid PhysicalRamDisk Path: $($dev.Path)"
        }

        default {
            throw "Unknown DevType: $($dev.DevType)"
        }
    }
}

# -------------------------------
# Phase 2 — Collect metadata + partition intent
# -------------------------------
$runtime = @()

foreach ($dev in $config) {

    $disk = Resolve-Disk $dev

    # Normalize PartitionsNeedMount to array
    $needMount = @()
    if ($dev.PSObject.Properties.Name -contains "PartitionsNeedMount" -and $dev.PartitionsNeedMount) {
        if ($dev.PartitionsNeedMount -is [System.Collections.IEnumerable] -and
            $dev.PartitionsNeedMount -isnot [string]) {
            $needMount = @($dev.PartitionsNeedMount)
        } else {
            $needMount = @($dev.PartitionsNeedMount)
        }
    }

    $meta = [ordered]@{
        Path                 = $dev.Path
        DevType              = $dev.DevType
        MountLabel           = $dev.MountLabel
        OpMode               = $dev.OpMode
        PartitionsNeedMount  = $needMount

        DiskNumber           = $disk.Number
        UniqueId             = $disk.UniqueId
        FriendlyName         = $disk.FriendlyName
        BusType              = $disk.BusType.ToString()
        Location             = $disk.Location
        SizeBytes            = $disk.Size
        PartitionStyle       = $disk.PartitionStyle.ToString()

        PartitionTotalCnt    = 0
        mountStatus          = "pending"
    }

    # Partition metadata
    $parts = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
    $plist = @()

    foreach ($p in $parts) {
        $pm = [ordered]@{
            PartitionNumber = $p.PartitionNumber
            SizeBytes       = $p.Size
            GptType         = $p.GptType
            MbrType         = $p.MbrType
            Type            = $p.Type

            FsType          = $null
            MountRequired   = $false
            PartitionMountLabel = $null
            MountStatus     = "pending"
        }

        # Filesystem detection
        try {
            $vol = Get-Volume -Partition $p -ErrorAction Stop
            $pm["FsType"] = $vol.FileSystem
        } catch {}

        # MountRequired logic
        $pm["MountRequired"] = $needMount -contains $p.PartitionNumber

        $plist += [pscustomobject]$pm
    }

    # PartitionTotalCnt
    $meta["PartitionTotalCnt"] = $plist.Count

    # PartitionMountLabel logic
    foreach ($pmObj in $plist) {
        if ($plist.Count -le 1) {
            $pmObj.PartitionMountLabel = $dev.MountLabel
        } else {
            $pmObj.PartitionMountLabel = ("{0}_p{1}" -f $dev.MountLabel, $pmObj.PartitionNumber)
        }
    }

    $meta["Partitions"] = $plist

    $runtime += [pscustomobject]$meta
}

# -------------------------------
# Phase 3 — Mount into WSL using PHYSICALDRIVE
# -------------------------------
foreach ($dev in $runtime) {
    $diskNum = $dev.DiskNumber
    $label   = $dev.MountLabel

    $phy = "\\.\PHYSICALDRIVE$diskNum"

    Write-Host "wsl --mount $phy --name $label"
    & wsl.exe --mount $phy --name $label
    $exit = $LASTEXITCODE

    if ($exit -eq 0) {
        $dev.mountStatus = "success"
    } else {
        $dev.mountStatus = "failed"
        Write-Warning "WSL mount failed for $phy (DiskNumber=$diskNum, Label=$label), exit code = $exit"
    }
}

# -------------------------------
# Phase 4 — Write runtime JSON
# -------------------------------
$runtime | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RuntimePath -Encoding UTF8
Write-Host "runtime-devices.json written."

Write-Host "=== generate-runtime.ps1 completed ==="

# --- Run process-runtime.ps1 if it exists in the same folder ---
$proc = Join-Path $PSScriptRoot "process-runtime.ps1"

if (Test-Path $proc) {
    Write-Host ""
    Write-Host "process-runtime.ps1 found. Running..."
    & $proc
} else {
    Write-Host ""
    Write-Host "process-runtime.ps1 not found in this folder. Skipping."
}
