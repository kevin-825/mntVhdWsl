<#
process-runtime.ps1
Consumes runtime-devices.json (grouped), mounts devices/partitions,
handles PhysicalRamDisk special-case, and writes runtime-devices-final.json.

Rules:
- Iterate groups dynamically (same order as runtime-devices.json)
- Detect device type via DevType
- If PartitionTotalCnt = 0 → mount whole disk (no --partition)
- If PartitionTotalCnt > 0 → mount only partitions with MountRequired = true
- PhysicalRamDisk special-case: format ext4 if needed, then mount whole disk
- Update mountStatus and PartitionMountStatus
#>

param(
    [string]$RuntimePath       = ".\runtime-devices.json",
    [string]$OutputRuntimePath = ".\runtime-devices-final.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== process-runtime.ps1 starting ==="

if (-not (Test-Path -LiteralPath $RuntimePath)) {
    throw "Runtime file not found: $RuntimePath"
}

# Load grouped runtime JSON
$runtime = Get-Content -LiteralPath $RuntimePath -Raw -Encoding UTF8 | ConvertFrom-Json

# ------------------------------------------------------------
# Helper: run WSL command and return stdout
# ------------------------------------------------------------
function Invoke-Wsl {
    param([string]$Command)
    return (& wsl.exe bash -lc "$Command" 2>$null) -join "`n"
}

# ------------------------------------------------------------
# Helper: find Linux disk node (/dev/sdX) by UniqueId ↔ ID_SERIAL_SHORT
# ------------------------------------------------------------
function Find-LinuxDiskByUniqueId {
    param([string]$UniqueId)

    Write-Host "  [ramdisk] Resolving Linux disk for UniqueId=$UniqueId"

    $lsblkJson = Invoke-Wsl "lsblk -J -o NAME,TYPE"
    if (-not $lsblkJson) { return $null }

    $lsblk = $lsblkJson | ConvertFrom-Json

    foreach ($devNode in $lsblk.blockdevices) {
        if ($devNode.type -ne "disk") { continue }

        $name = $devNode.name
        $udevOut = Invoke-Wsl "udevadm info --query=property --name=/dev/$name | grep '^ID_SERIAL_SHORT=' || true"
        if (-not $udevOut) { continue }

        $line = ($udevOut -split "`n") | Where-Object { $_ -like 'ID_SERIAL_SHORT=*' } | Select-Object -First 1
        if (-not $line) { continue }

        $short = ($line -split "=",2)[1].Trim()

        if ($short -eq $UniqueId) {
            Write-Host "  [ramdisk] Matched UniqueId=$UniqueId to /dev/$name"
            return "/dev/$name"
        }
    }

    Write-Warning "  [ramdisk] No Linux disk found for UniqueId=$UniqueId"
    return $null
}

# ------------------------------------------------------------
# Special-case handler for PhysicalRamDisk
# ------------------------------------------------------------
function Handle-RamDiskSpecialCase {
    param($dev)

    Write-Host "  [ramdisk] Special-case handling for $($dev.MountLabel)"

    $phy = "\\.\PHYSICALDRIVE$($dev.DiskNumber)"

    # ------------------------------------------------------------
    # 1. Try whole-disk mount
    # ------------------------------------------------------------
    Write-Host "  [ramdisk] Trying whole-disk mount..."
    & wsl.exe --mount $phy --name $dev.MountLabel

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [ramdisk] Whole-disk mount succeeded."
        foreach ($pm in $dev.Partitions) {
            if ($pm.MountRequired) { $pm.PartitionMountStatus = "success" }
        }
        $dev.mountStatus = "success"
        return
    }

    Write-Host "  [ramdisk] Whole-disk mount failed. Trying partition mount..."

    # ------------------------------------------------------------
    # 2. Try partition mount (if exists)
    # ------------------------------------------------------------
    if ($dev.Partitions.Count -gt 0) {
        $partNum = $dev.Partitions[0].PartitionNumber
        Write-Host "  [ramdisk] Trying partition mount..."
        & wsl.exe --mount $phy --partition $partNum --name $dev.MountLabel

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [ramdisk] Partition mount succeeded."
            foreach ($pm in $dev.Partitions) {
                if ($pm.MountRequired) { $pm.PartitionMountStatus = "success" }
            }
            $dev.mountStatus = "success"
            return
        }

        Write-Host "  [ramdisk] Partition mount failed."
    }

    # ------------------------------------------------------------
    # 3. Format whole disk and mount again
    # ------------------------------------------------------------
    Write-Host "  [ramdisk] Resolving Linux disk path for formatting..."
    $linuxDisk = Find-LinuxDiskByUniqueId -UniqueId $dev.UniqueId
    if (-not $linuxDisk) {
        Write-Warning "  [ramdisk] Cannot resolve Linux disk. Marking failed."
        $dev.mountStatus = "failed"
        foreach ($pm in $dev.Partitions) { $pm.PartitionMountStatus = "failed" }
        return
    }

    Write-Host "  [ramdisk] Formatting whole disk as ext4..."
    & wsl.exe bash -lc "sudo mkfs.ext4 -F $linuxDisk"

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  [ramdisk] mkfs.ext4 failed."
        $dev.mountStatus = "failed"
        foreach ($pm in $dev.Partitions) { $pm.PartitionMountStatus = "failed" }
        return
    }

    Write-Host "  [ramdisk] mkfs.ext4 succeeded. Re-mounting..."

    & wsl.exe --mount $phy --name $dev.MountLabel

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  [ramdisk] Mount after format failed."
        $dev.mountStatus = "failed"
        foreach ($pm in $dev.Partitions) { $pm.PartitionMountStatus = "failed" }
        return
    }

    foreach ($pm in $dev.Partitions) {
        if ($pm.MountRequired) { $pm.PartitionMountStatus = "success" }
    }

    $dev.mountStatus = "success"
    Write-Host "  [ramdisk] Mounted successfully after format."
}

# ------------------------------------------------------------
# Normal handler for PhysicalHardDisk
# ------------------------------------------------------------
function Handle-Physical {
    param($dev)

    $phy = "\\.\PHYSICALDRIVE$($dev.DiskNumber)"

    # Case 1: whole disk mount
    if ($dev.PartitionTotalCnt -eq 0) {
        Write-Host "  Mounting whole disk as '$($dev.MountLabel)'..."
        & wsl.exe --mount $phy --name $dev.MountLabel

        if ($LASTEXITCODE -eq 0) {
            $dev.mountStatus = "success"
        } else {
            $dev.mountStatus = "failed"
        }
        return
    }

    # Case 2: mount required partitions
    foreach ($pm in $dev.Partitions) {
        if (-not $pm.MountRequired) { continue }

        $pNum   = [int]$pm.PartitionNumber
        $pLabel = $pm.PartitionMountLabel

        Write-Host "  Mounting partition #$pNum as '$pLabel'..."
        & wsl.exe --mount $phy --name $pLabel --partition $pNum

        if ($LASTEXITCODE -eq 0) {
            $pm.PartitionMountStatus = "success"
        } else {
            $pm.PartitionMountStatus = "failed"
        }
    }

    # Device success only if all required partitions succeeded
    $failed = @(
        $dev.Partitions | Where-Object { $_.MountRequired -and $_.PartitionMountStatus -ne "success" }
    )

    $dev.mountStatus = if ($failed.Count -eq 0) { "success" } else { "failed" }
}

# ------------------------------------------------------------
# Handler for MsftVHD
# ------------------------------------------------------------
function Handle-VHDX {
    param($dev)

    $path = $dev.Path

    # Case 1: whole disk mount
    if ($dev.PartitionTotalCnt -eq 0) {
        Write-Host "  Mounting whole VHDX as '$($dev.MountLabel)'..."
        & wsl.exe --mount $path --vhd --name $dev.MountLabel

        if ($LASTEXITCODE -eq 0) {
            $dev.mountStatus = "success"
        } else {
            $dev.mountStatus = "failed"
        }
        return
    }

    # Case 2: mount required partitions
    foreach ($pm in $dev.Partitions) {
        if (-not $pm.MountRequired) { continue }

        $pNum   = [int]$pm.PartitionNumber
        $pLabel = $pm.PartitionMountLabel

        Write-Host "  Mounting VHDX partition #$pNum as '$pLabel'..."
        & wsl.exe --mount $path --vhd --name $pLabel --partition $pNum

        if ($LASTEXITCODE -eq 0) {
            $pm.PartitionMountStatus = "success"
        } else {
            $pm.PartitionMountStatus = "failed"
        }
    }

    # Device success only if all required partitions succeeded
    $failed = @(
        $dev.Partitions | Where-Object { $_.MountRequired -and $_.PartitionMountStatus -ne "success" }
    )

    $dev.mountStatus = if ($failed.Count -eq 0) { "success" } else { "failed" }
}

# ------------------------------------------------------------
# MAIN LOOP — iterate groups dynamically
# ------------------------------------------------------------
foreach ($groupName in $runtime.PSObject.Properties.Name) {

    Write-Host ""
    Write-Host "=== Processing group: $groupName ==="

    foreach ($dev in $runtime.$groupName) {

        Write-Host ""
        Write-Host "Device: $($dev.MountLabel) (DevType=$($dev.DevType), Status=$($dev.mountStatus))"
		
		# ----------------------------------------------------
		# ✔ Skip already-successful devices BEFORE switch
		# ----------------------------------------------------
		if ($dev.mountStatus -eq "success") {
			Write-Host "  [skip] Already mounted. Skipping."
			continue
		}

        switch ($dev.DevType) {
		
            "PhysicalRamDisk" {
                Handle-RamDiskSpecialCase $dev
            }
		
            "PhysicalHardDisk" {
                Handle-Physical $dev
            }
		
            "MsftVHD" {
                Handle-VHDX $dev
            }
		
            default {
                #Write-Warning "Unknown DevType '$($dev.DevType)' — marking as error."      long —  will broke the code and won't run.
				Write-Warning "Unknown DevType '$($dev.DevType)' - marking as error."
                $dev.mountStatus = "error"
            }
        }
    }
}

# ------------------------------------------------------------
# Write final JSON (preserve grouping)
# ------------------------------------------------------------
$runtime | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RuntimePath -Encoding UTF8
$runtime | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputRuntimePath -Encoding UTF8

Write-Host ""
Write-Host "Final runtime written to: $OutputRuntimePath"
Write-Host "=== process-runtime.ps1 completed ==="

# ------------------------------------------------------------
# Generate .bash_aliases_1 and dockerVolumes variable
# ------------------------------------------------------------
Write-Host "Generating .bash_aliases_1 and docker volume hints..."

$aliasFile = Join-Path $PSScriptRoot ".bash_aliases_1"

# Start fresh (ASCII, CRLF)
"" | Set-Content $aliasFile -Encoding Ascii

# Collect docker -v lines
$dockerList = @()

foreach ($groupName in $runtime.PSObject.Properties.Name) {
    $group = $runtime.$groupName

    foreach ($dev in $group) {

        if ($dev.mountStatus -ne "success") { continue }

        $diskNum    = $dev.DiskNumber
        $devType    = $dev.DevType
        $mountLabel = $dev.MountLabel

        # Successful partitions
        $parts = @(
            $dev.Partitions |
            Where-Object { $_.MountRequired -and $_.PartitionMountStatus -eq "success" }
        )

        # Determine prefix and alias number
        if ($devType -eq "MsftVHD") {
            if ($mountLabel -match "\d+$") {
                $N = $Matches[0]
            } else {
                $N = $diskNum
            }
            $prefix      = "v"
            $aliasNumber = $N
        }
        else {
            $prefix      = "d"
            $aliasNumber = $diskNum
        }

        # ------------------------------------------------------------
        # Case 1: zero or one partition
        # ------------------------------------------------------------
        if ($parts.Count -le 1) {

            # Alias
            Add-Content -Encoding Ascii $aliasFile "alias cd2${prefix}${aliasNumber}='cd /mnt/wsl/${mountLabel}'"
            Add-Content -Encoding Ascii $aliasFile ""

            # Docker -v
            $dockerList += "-v /mnt/wsl/${mountLabel}:/mnt/wsl/${mountLabel} \"

            continue
        }

        # ------------------------------------------------------------
        # Case 2: multiple partitions
        # ------------------------------------------------------------
        foreach ($pm in $parts) {
            $pLabel = $pm.PartitionMountLabel
            $pNum   = $pm.PartitionNumber

            # Alias
            Add-Content -Encoding Ascii $aliasFile "alias cd2${prefix}${aliasNumber}p${pNum}='cd /mnt/wsl/${pLabel}'"
            Add-Content -Encoding Ascii $aliasFile ""

            # Docker -v
            $dockerList += "-v /mnt/wsl/${pLabel}:/mnt/wsl/${pLabel} \"
        }
    }
}

# ------------------------------------------------------------
# Write dockerVolumes variable at the end of alias file
# ------------------------------------------------------------
Add-Content -Encoding Ascii $aliasFile 'dockerVolumes="\'
foreach ($line in $dockerList) {
    Add-Content -Encoding Ascii $aliasFile $line
}
Add-Content -Encoding Ascii $aliasFile '"'

Write-Host "Alias file created at: $aliasFile"
Write-Host ""
# ------------------------------------------------------------
# Copy alias file into WSL home
# ------------------------------------------------------------
$aliasSrc  = Join-Path $PSScriptRoot ".bash_aliases_1"
$aliasDest = "\\wsl$\Ubuntu-24.04\home\kflyn\.bash_aliases_1"

Copy-Item $aliasSrc $aliasDest -Force
Write-Host "Copied .bash_aliases_1 into $aliasDest"
Write-Host ""

# ------------------------------------------------------------
# Verify mountpoints inside WSL
# ------------------------------------------------------------
Write-Host "Verifying mounted devices inside WSL..."
Write-Host ""

$MOUNT_BASE = "/mnt/wsl"
$findOutput = Invoke-Wsl "find $MOUNT_BASE -mindepth 2 -maxdepth 2"

if ($findOutput) {
    Write-Host $findOutput
} else {
    Write-Warning "No mountpoints found under $MOUNT_BASE. Something may be wrong."
}
Write-Host ""
