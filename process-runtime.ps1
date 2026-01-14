<#
process-runtime.ps1
Phase 2: consume runtime-devices.json, mount all required partitions,
handle PhysicalRamDisk only when FsType != ext4, and output final JSON.

Input:  runtime-devices.json
Output: runtime-devices-final.json
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

# Load runtime devices
$runtime = Get-Content -LiteralPath $RuntimePath -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "Loaded $($runtime.Count) runtime devices."

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
# Determine if this device needs special ramdisk handling
# ------------------------------------------------------------
function Is-RamDiskSpecialCase {
    param($dev)

    if ($dev.DevType -ne "PhysicalRamDisk") {
        return $false
    }

    # If any FsType says ext4 → normal case
    $fs = $dev.Partitions | Select-Object -ExpandProperty FsType -First 1
    if ($fs -eq "ext4") {
        return $false
    }

    # Otherwise → special case
    return $true
}

# ------------------------------------------------------------
# Special-case handler for PhysicalRamDisk
# ------------------------------------------------------------
function Handle-RamDiskSpecialCase {
    param($dev)

    Write-Host "  [ramdisk] Special-case handling for $($dev.MountLabel)"

    $linuxDisk = Find-LinuxDiskByUniqueId -UniqueId $dev.UniqueId
    if (-not $linuxDisk) {
        Write-Warning "  [ramdisk] Cannot resolve Linux disk. Marking failed."
        $dev.mountStatus = "failed"
        foreach ($pm in $dev.Partitions) { $pm.MountStatus = "failed" }
        return
    }

    # Format whole disk as EXT4
Write-Host "  [ramdisk] mkfs.ext4 -F $linuxDisk"

# Run sudo interactively (NO redirection here)
$mkfsOutput = & wsl.exe bash -lc "sudo mkfs.ext4 -F $linuxDisk"

# Now check exit code
if ($LASTEXITCODE -ne 0) {
    Write-Warning "  [ramdisk] mkfs.ext4 failed for $linuxDisk"
    $dev.mountStatus = "failed"
    foreach ($pm in $dev.Partitions) { $pm.MountStatus = "failed" }
    return
}

Write-Host "  [ramdisk] mkfs.ext4 succeeded."

    # Mount via WSL
    $phy = "\\.\PHYSICALDRIVE$($dev.DiskNumber)"
    Write-Host "  [ramdisk] wsl --mount $phy --name $($dev.MountLabel)"
    & wsl.exe --mount $phy --name $dev.MountLabel
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  [ramdisk] WSL mount failed."
        $dev.mountStatus = "failed"
        foreach ($pm in $dev.Partitions) { $pm.MountStatus = "failed" }
        return
    }

    # Mark all required partitions as success
    foreach ($pm in $dev.Partitions) {
        if ($pm.MountRequired) { $pm.MountStatus = "success" }
    }
	$dev.Partitions = @()
    $dev.mountStatus = "success"
    Write-Host "  [ramdisk] Mounted successfully."

    # Update FsType and partition metadata after formatting
    #$dev.Partitions[0].FsType = "ext4"
    #$dev.Partitions[0].PartitionNumber = 0
    #$dev.PartitionTotalCnt = 0
    #$dev.Partitions[0].MountRequired = $true
    #$dev.Partitions[0].MountStatus = "success"
}

# ------------------------------------------------------------
# Normal device handler (use --partition)
# ------------------------------------------------------------
function Handle-NormalDevice {
    param($dev)

    $phy = "\\.\PHYSICALDRIVE$($dev.DiskNumber)"

    foreach ($pm in $dev.Partitions) {
        if (-not $pm.MountRequired) { continue }
        if ($pm.MountStatus -eq "success") { continue }

        $pNum   = [int]$pm.PartitionNumber
        $pLabel = $pm.PartitionMountLabel

        Write-Host "  Mounting partition #$pNum as '$pLabel'..."
        & wsl.exe --mount $phy --name $pLabel --partition $pNum

        if ($LASTEXITCODE -eq 0) {
            Write-Host "    Success."
            $pm.MountStatus = "success"
        } else {
            Write-Warning "    Failed."
            $pm.MountStatus = "failed"
        }
    }

    # Device success only if all required partitions succeeded
    #$failed = $dev.Partitions | Where-Object { $_.MountRequired -and $_.MountStatus -ne "success" }

    $failed = @(
        $dev.Partitions | Where-Object { $_.MountRequired -and $_.MountStatus -ne "success" }
    )

    $dev.mountStatus = if ($failed.Count -eq 0) { "success" } else { "failed" }

    # Update partition count
    $dev.PartitionTotalCnt = $dev.Partitions.Count

    # Update FsType for each partition
    foreach ($pm in $dev.Partitions) {
        if ($pm.MountRequired -and $pm.MountStatus -eq "success") {

        }
    }

    # If single-partition disk, update device-level FsType
    if ($dev.Partitions.Count -eq 1) {
        #$dev.FsType = $dev.Partitions[0].FsType
    }
}

# ------------------------------------------------------------
# MAIN LOOP
# ------------------------------------------------------------
foreach ($dev in $runtime) {
    Write-Host ""
    Write-Host "Processing device: $($dev.MountLabel) (DevType=$($dev.DevType), Status=$($dev.mountStatus))"

    switch ($dev.mountStatus) {

        "success" {
            Write-Host "  [skip] Already mounted successfully. Skipping."
            continue
        }

        "failed" {
            if ($dev.DevType -eq "PhysicalRamDisk") {
                Handle-RamDiskSpecialCase $dev
            } else {
                Handle-NormalDevice $dev
            }
            continue
        }

        "pending" {
            if ($dev.DevType -eq "PhysicalRamDisk") {
                Handle-RamDiskSpecialCase $dev
            } else {
                Handle-NormalDevice $dev
            }
            continue
        }

        default {
            Write-Warning ("  Unknown mountStatus '{0}' - treating as failed." -f $dev.mountStatus)
            if ($dev.DevType -eq "PhysicalRamDisk") {
                Handle-RamDiskSpecialCase $dev
            } else {
                Handle-NormalDevice $dev
            }
        }
    }
}

# ------------------------------------------------------------
# Write final JSON
# ------------------------------------------------------------
$runtime | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RuntimePath -Encoding UTF8
$runtime | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputRuntimePath -Encoding UTF8

Write-Host ""
Write-Host "Final runtime written to: $OutputRuntimePath"
Write-Host "=== process-runtime.ps1 completed ==="


Write-Host ""
Write-Host "Use the following to run docker container if needed:"
Write-Host ""

foreach ($dev in $runtime) {

    # Skip devices that failed
    if ($dev.mountStatus -ne "success") { continue }

    # Collect successful partitions
    $partitions = $dev.Partitions | Where-Object { $_.MountRequired -and $_.MountStatus -eq "success" }

    # Normalize to array
    $partitions = @($partitions)

    # Case 1: zero or one partition
    if ($partitions.Count -le 1) {
        $label = $dev.MountLabel
        Write-Host ("-v /mnt/wsl/{0}:/mnt/wsl/{0} \" -f $label)
        continue
    }

    # Case 2: multiple partitions
    foreach ($pm in $partitions) {
        $pLabel = $pm.PartitionMountLabel
        Write-Host ("-v /mnt/wsl/{0}:/mnt/wsl/{0} \" -f $pLabel)
    }
}

Write-Host ""


Write-Host ""
Write-Host "Verifying mounted devices inside WSL..."
Write-Host ""

# Base mount directory inside WSL
$MOUNT_BASE = "/mnt/wsl"

# Run find command to list all mountpoints 2 levels deep
$findOutput = Invoke-Wsl "find $MOUNT_BASE -mindepth 2 -maxdepth 2"

if ($findOutput) {
    Write-Host $findOutput
} else {
    Write-Warning "No mountpoints found under $MOUNT_BASE. Something may be wrong."
}

Write-Host ""

# --- Create .bash_aliases_1 with cd2* aliases (not installing) ---

Write-Host ""
Write-Host "Generating .bash_aliases_1 (not installing)..."

$aliasFile = Join-Path $PSScriptRoot ".bash_aliases_1"

# Start fresh (ASCII, but CRLF because of PS 5.1)
"" | Set-Content $aliasFile -Encoding Ascii

foreach ($dev in $runtime) {

    if ($dev.mountStatus -ne "success") { continue }

    $diskNum    = $dev.DiskNumber
    $devType    = $dev.DevType
    $mountLabel = $dev.MountLabel

    # Successful partitions
    $parts = @($dev.Partitions | Where-Object { $_.MountRequired -and $_.MountStatus -eq "success" })

    # Determine prefix and alias number
    if ($devType -eq "VirtualVhdx") {
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

    # Zero or one partition
    if ($parts.Count -le 1) {
        Add-Content -Encoding Ascii $aliasFile "alias cd2${prefix}${aliasNumber}='cd /mnt/wsl/${mountLabel}'"
        continue
    }

    # Multiple partitions
    foreach ($pm in $parts) {
        $pLabel = $pm.PartitionMountLabel
        $pNum   = $pm.PartitionNumber
        Add-Content -Encoding Ascii $aliasFile "alias cd2${prefix}${aliasNumber}p${pNum}='cd /mnt/wsl/${pLabel}'"
    }
}

Write-Host "Alias file created at: $aliasFile"
Write-Host ""


# Copy into ramdisk0 (PHYSICALDRIVE5 PhysicalRamDisk)
#$ramdisk = $runtime | Where-Object {
#    $_.DevType -eq "PhysicalRamDisk" -and
#    $_.Path -eq "\\.\PHYSICALDRIVE5" -and
#    $_.mountStatus -eq "success"
#}
#
#if ($ramdisk) {
#	$mountPath = "/mnt/wsl/$($ramdisk.MountLabel)"
#	$owner = wsl -d Ubuntu-24.04 -e stat -c %U $mountPath
#	if ($owner -eq "root") {
#		Write-Host "→ Fixing ownership on $mountPath"
#		wsl -d Ubuntu-24.04 -e sudo chown -R kflyn:kflyn $mountPath
#	} else {
#		Write-Host "→ Ownership already correct ($owner), skipping chown"
#	}
#}

$aliasSrc  = Join-Path $PSScriptRoot ".bash_aliases_1"
$aliasDest = "\\wsl$\Ubuntu-24.04\home\kflyn\.bash_aliases_1"
Copy-Item $aliasSrc $aliasDest -Force
Write-Host "Copied .bash_aliases_1 into $aliasDest"