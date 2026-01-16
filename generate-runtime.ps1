<# 
Dynamic generate-runtime.ps1

- Reads group names dynamically from devices.json
- Processes devices dynamically (no hard-coded group names)
- Physical devices: use DiskNumber from devices.json
- VHDX devices: attach → read partitions → detach → DiskNumber=null
- Universal partition schema:
    PartitionNumber
    SizeMB
    SizeGB
    GptType
    MbrType
    Type
    FsType
    MountRequired
    PartitionMountLabel
    PartitionMountStatus
- Device-level mountStatus = "pending"
- PartitionMountStatus = "pending"
- PartitionMountLabel rules:
    - If 0 or 1 partition → MountLabel
    - If >=2 partitions → MountLabel_pN
#>

param(
    [string]$ConfigPath,
    [string]$RuntimePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot "devices.json"
}

if (-not $RuntimePath) {
    $RuntimePath = Join-Path $PSScriptRoot "runtime-devices.json"
}

Write-Host "=== generate-runtime.ps1 (Dynamic Version) starting ==="

# -------------------------------
# Load devices.json
# -------------------------------
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$configRoot = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json


function Update-DiskNumbersFromWindows {
    param(
        [Parameter(Mandatory)]
        [object]$configRoot
    )

    Write-Host ""
    Write-Host "=== Updating DiskNumber from Windows (Physical disks only) ==="

    # Read all Windows disks
    $winDisks = Get-Disk | Select-Object Number, FriendlyName, UniqueId

    foreach ($groupName in $configRoot.PSObject.Properties.Name) {
        $group = $configRoot.$groupName

        foreach ($dev in $group) {

            # Skip VHDX devices entirely
            if ($dev.DevType -eq "VirtualVhdx" -or $dev.DevType -eq "MsftVHD") {
                Write-Host "  Skipping VHDX device $($dev.MountLabel) (DevType=$($dev.DevType))"
                continue
            }

            # Skip if no UniqueId
            if (-not $dev.UniqueId) {
                Write-Warning "  Device $($dev.MountLabel) has no UniqueId. Skipping."
                continue
            }

            # Normalize UniqueId for comparison
            $targetId = $dev.UniqueId.Trim().ToLower()

            # Match by UniqueId
            $match = $winDisks | Where-Object {
                $_.UniqueId -and $_.UniqueId.Trim().ToLower() -eq $targetId
            }

            if ($match) {
                $dev.DiskNumber = $match.Number
                Write-Host "  Updated: $($dev.MountLabel) → DiskNumber=$($dev.DiskNumber)"
            }
            else {
                Write-Warning "  Could not match UniqueId=$($dev.UniqueId) for $($dev.MountLabel). DiskNumber unchanged."
            }
        }
    }

    Write-Host "=== DiskNumber update complete ==="
    Write-Host ""
}

# Update DiskNumber for physical disks only
Update-DiskNumbersFromWindows -configRoot $configRoot


# runtime output structure mirrors devices.json groups
$runtime = [ordered]@{}




# -------------------------------
# Helper: Build partition metadata list
# -------------------------------
function New-PartitionMetadataList {
    param(
        [Parameter(Mandatory)]
        [object]$DeviceConfig,
        [Parameter(Mandatory)]
        [array]$Partitions
    )

    $plist = @()

    # Normalize PartitionsNeedMount
    $needMount = @()
    if ($DeviceConfig.PSObject.Properties.Name -contains "PartitionsNeedMount" -and $DeviceConfig.PartitionsNeedMount) {
        if ($DeviceConfig.PartitionsNeedMount -is [System.Collections.IEnumerable] -and
            $DeviceConfig.PartitionsNeedMount -isnot [string]) {
            $needMount = @($DeviceConfig.PartitionsNeedMount)
        } else {
            $needMount = @($DeviceConfig.PartitionsNeedMount)
        }
    }

    foreach ($p in $Partitions) {
        $pm = [ordered]@{
            PartitionNumber       = $p.PartitionNumber
            SizeMB                = $null
            SizeGB                = $null
            GptType               = $p.GptType
            MbrType               = $p.MbrType
            Type                  = $p.Type
            FsType                = $null
            MountRequired         = $false
            PartitionMountLabel   = $null
            PartitionMountStatus  = "pending"
        }

        # SizeMB / SizeGB
        if ($p.Size -ne $null) {
            $pm.SizeMB = [math]::Round($p.Size / 1MB)
            $pm.SizeGB = [math]::Round($p.Size / 1GB, 2)
        }

        # Filesystem detection
        try {
            $vol = Get-Volume -Partition $p -ErrorAction Stop
            $pm.FsType = $vol.FileSystem
        } catch {}

        # MountRequired
        $pm.MountRequired = $needMount -contains $p.PartitionNumber

        $plist += [pscustomobject]$pm
    }

    # PartitionMountLabel rules
    $total = $plist.Count
    foreach ($pmObj in $plist) {
        if ($total -le 1) {
            $pmObj.PartitionMountLabel = $DeviceConfig.MountLabel
        } else {
            $pmObj.PartitionMountLabel = ("{0}_p{1}" -f $DeviceConfig.MountLabel, $pmObj.PartitionNumber)
        }
    }

    return ,$plist
}

# -------------------------------
# Track VHDs we attach
# -------------------------------
$attachedVhds = @()

# -------------------------------
# Process each group dynamically
# -------------------------------
foreach ($groupName in $configRoot.PSObject.Properties.Name) {

    Write-Host "Processing group: $groupName"

    $groupDevices = @($configRoot.$groupName)
    $runtime.$groupName = @()

    foreach ($dev in $groupDevices) {

        Write-Host "  Device UniqueId=$($dev.UniqueId) MountLabel=$($dev.MountLabel)"

        $isVhd = $false
        $diskNumber = $null
        $partitions = @()
        $partitionTotalCnt = 0
        $deviceMountStatus = "pending"

        # Determine device type dynamically
        if ($dev.Path) {
            $isVhd = $true
        } elseif ($dev.PSObject.Properties.Name -contains "DiskNumber") {
            $isVhd = $false
        } else {
            Write-Warning "Device UniqueId=$($dev.UniqueId) has neither Path nor DiskNumber. Marking as error."
            $deviceMountStatus = "error"
        }

        # -------------------------------
        # Physical device
        # -------------------------------
        if (-not $isVhd -and $deviceMountStatus -ne "error") {
            try {
                $diskNumber = [int]$dev.DiskNumber
                $parts = @( Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue )

                if ($parts.Count -gt 0) {
                    $partitions = New-PartitionMetadataList -DeviceConfig $dev -Partitions $parts
                    $partitionTotalCnt = $partitions.Count
                }
            } catch {
                Write-Warning ("Failed to process Physical device UniqueId={0}: {1}" -f $dev.UniqueId, $_.Exception.Message)
                $deviceMountStatus = "error"
            }
        }

        # -------------------------------
        # VHDX device
        # -------------------------------
        if ($isVhd -and $deviceMountStatus -ne "error") {
            $vhdPath = $dev.Path

            if ($vhdPath -like "\\?\*") {
                $vhdPath = $vhdPath.Substring(4)
            }

            try {
                $vhd = Get-VHD -Path $vhdPath -ErrorAction SilentlyContinue
                if (-not $vhd -or -not $vhd.Attached) {
                    Write-Host "    Attach-VHD $vhdPath"
                    Mount-VHD -Path $vhdPath -NoDriveLetter -ErrorAction Stop
                    $vhd = Get-VHD -Path $vhdPath -ErrorAction Stop
                    $attachedVhds += $vhdPath
                } else {
                    $attachedVhds += $vhdPath
                }

                $diskNumber = $vhd.DiskNumber
                $parts = @( Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue )

                if ($parts.Count -gt 0) {
                    $partitions = New-PartitionMetadataList -DeviceConfig $dev -Partitions $parts
                    $partitionTotalCnt = $partitions.Count
                }

            } catch {
                Write-Warning ("Failed to process VHDX Path={0}: {1}" -f $vhdPath, $_.Exception.Message)
                $deviceMountStatus = "error"
            }

            # VHDX always outputs DiskNumber=null
            $diskNumber = $null
        }

        # -------------------------------
        # Build runtime device entry
        # -------------------------------
        $meta = [ordered]@{
            UniqueId            = $dev.UniqueId
            DevType             = $dev.DevType
            Path                = $dev.Path
            MountLabel          = $dev.MountLabel
            PartitionsNeedMount = $dev.PartitionsNeedMount
            SizeMB              = $dev.SizeMB
            SizeGB              = $dev.SizeGB
            PartitionStyle      = $dev.PartitionStyle

            DiskNumber          = $diskNumber
            PartitionTotalCnt   = $partitionTotalCnt
            mountStatus         = $deviceMountStatus
            Partitions          = $partitions
        }

        $runtime.$groupName += [pscustomobject]$meta
    }
}

# -------------------------------
# Detach all VHDs we attached
# -------------------------------
$attachedVhds = $attachedVhds | Select-Object -Unique
foreach ($path in $attachedVhds) {
    try {
        Write-Host "Dismount-VHD $path"
        Dismount-VHD -Path $path -ErrorAction Stop
    } catch {
        Write-Warning ("Failed to dismount VHD {0}: {1}" -f $path, $_.Exception.Message)
    }
}
Write-Host ""
Write-Host "=== Pre-clean: Offlining physical disks in Windows ==="

$seen = @{}   # prevents offlining the same disk twice

foreach ($groupName in $configRoot.PSObject.Properties.Name) {
    foreach ($dev in $configRoot.$groupName) {

        if ($dev.DevType -eq "PhysicalHardDisk" -or $dev.DevType -eq "PhysicalRamDisk") {

            $diskNum = $dev.DiskNumber
            if ($diskNum -ne $null -and -not $seen.ContainsKey($diskNum)) {

                $seen[$diskNum] = $true

                Write-Host "  Offlining PHYSICALDRIVE$diskNum..."
                try {
                    Set-Disk -Number $diskNum -IsOffline $true -ErrorAction Stop
                } catch {
                    Write-Warning ("  Failed to offline disk {0}: {1}" -f $diskNum, $_.Exception.Message)
                }
            }
        }
    }
}

# -------------------------------
# Write runtime-devices.json
# -------------------------------
try {
    $runtime | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RuntimePath -Encoding UTF8
    Write-Host "runtime-devices.json written to $RuntimePath"
} catch {
    throw "Failed to write runtime-devices.json: $($_.Exception.Message)"
}

Write-Host "=== generate-runtime.ps1 (Dynamic Version) completed ==="
