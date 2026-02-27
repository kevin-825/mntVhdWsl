#requires -Version 5.1

$scriptDir                = Split-Path -Parent $MyInvocation.MyCommand.Definition
$default_physicalConfigFile = Join-Path $scriptDir "default_physical_disks.txt"
$default_vhdConfigFile      = Join-Path $scriptDir "default_vhdx_files.txt"
$default_vhdSelectFile      = Join-Path $scriptDir "default_vhdx_select_files.txt"

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Relaunching script as Administrator..."
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ErrorActionPreference = 'Stop'

# --------------------------------------------------
# Helper: show disk info + partitions
# --------------------------------------------------
function Show-DiskInfo {
    param ($Disk)
    try {
        Write-Host ("DiskNumber:{0}  FriendlyName:`"{1}`"  UniqueID:{2}" -f $Disk.Number, $Disk.FriendlyName, $Disk.UniqueId)

        $indent = "`t`t`t"
        try {
            $parts = Get-Partition -DiskNumber $Disk.Number -ErrorAction Stop
        } catch {
            Write-Warning "Cannot get partitions for DiskNumber $($Disk.Number): $($_.Exception.Message)"
            $parts = @()
        }

        if ($parts) {
            $rows = @()
            foreach ($p in $parts) {
                try {
                    $vol = Get-Volume -Partition $p -ErrorAction Stop
                } catch {
                    $vol = $null
                }
                $rows += [PSCustomObject]@{
                    PartitionN  = if ($p.PartitionNumber) { $p.PartitionNumber } else { 'unknown' }
                    DriveLetter = if ($vol -and $vol.DriveLetter) { $vol.DriveLetter } else { 'unknown' }
                    Label       = if ($vol -and $vol.FileSystemLabel) { $vol.FileSystemLabel } else { 'unknown' }
                    FsType      = if ($vol -and $vol.FileSystem) { $vol.FileSystem } else { 'unknown' }
                }
            }

            $table = $rows | Format-Table -AutoSize | Out-String
            $table -split "`r?`n" | ForEach-Object { Write-Host ($indent + $_) }
        }
        else {
            Write-Host ($indent + "PartitionN DriveLetter Label FsType")
            Write-Host ($indent + "---------- ----------- ----- ------")
            Write-Host ($indent + "unknown    unknown     unknown unknown")
        }
        Write-Host ""
    } catch {
        Write-Warning "Failed to display disk info for DiskNumber $($Disk.Number): $($_.Exception.Message)"
    }
}

# --------------------------------------------------
# STEP 1: Physical disks
# --------------------------------------------------
try {
    $physicalDisks = Get-Disk -ErrorAction Stop |
        Where-Object BusType -ne 'File Backed Virtual' |
        Sort-Object Number
} catch {
    Write-Warning "Cannot get physical disks: $($_.Exception.Message)"
    $physicalDisks = @()
}

Write-Host "`n=== Physical Disks ==="
foreach ($d in $physicalDisks) {
    Show-DiskInfo $d
}

# Prompt or read saved selection
try {
    if (Test-Path $default_physicalConfigFile) {
        $inputLine = Get-Content $default_physicalConfigFile -Raw
        Write-Host "Using saved physical disk selection: $inputLine"
    } else {
        Write-Host ""
        Write-Host "Select physical devices to mount."
        Write-Host "Format: DiskNumber[partition1,partition2,...] e.g. 6[1,2] 1[]"
        $inputLine = Read-Host "Enter selection"
        Set-Content -Path $default_physicalConfigFile -Value $inputLine -Encoding UTF8
        Write-Host "Selection saved to $default_physicalConfigFile"
    }
} catch {
    Write-Warning "Error reading/saving physical disk selection: $($_.Exception.Message)"
    $inputLine = ""
}

$tokens = $inputLine -split '\s+'

$result = @{
    Physical = @()
    MsftVHD  = @()
}

foreach ($token in $tokens) {
    if ($token -match '^(\d+)\[(.*?)\]$') {
        $diskNum = [int]$matches[1]
        $parts   = @()
        if ($matches[2]) {
            foreach ($p in ($matches[2] -split ',')) {
                if ($p -match '^\d+$') { $parts += [int]$p }
            }
        }

        try {
            $disk = Get-Disk -Number $diskNum -ErrorAction Stop
        } catch {
            Write-Warning ("Cannot find disk number {0}: {1}" -f $diskNum, $_.Exception.Message)
            continue
        }

        $devType = if ($disk.FriendlyName -match 'RAMDisk') { 'PhysicalRamDisk' } else { 'PhysicalHardDisk' }

        $result.Physical += [ordered]@{
            DiskNumber          = $diskNum
            UniqueId            = $disk.UniqueId
            FriendlyName        = $disk.FriendlyName
            DevType             = $devType
            Path                = $null
            SizeMB              = [math]::Round($disk.Size / 1MB)
            SizeGB              = [math]::Round($disk.Size / 1GB, 2)
            PartitionStyle      = $disk.PartitionStyle
            MountLabel          = if ($devType -eq 'PhysicalRamDisk') { "ramdisk$diskNum" } else { "disk$diskNum" }
            MountStatus         = 'unknown'
            PartitionsNeedMount = $parts
        }
    }
}

# --------------------------------------------------
# STEP 2A: VHD/VHDX paths → build MsftVHD entries
# --------------------------------------------------
try {
    if (Test-Path $default_vhdConfigFile) {
        $vhdInput = Get-Content $default_vhdConfigFile -Raw
        Write-Host "Using saved VHD/VHDX paths: $vhdInput"
    } else {
        Write-Host ""
        Write-Host "Step 2: Enter paths to VHD/VHDX files you want to attach."
        Write-Host "Separate multiple paths with space, e.g.:"
        Write-Host "D:\VirtualMachines\vhds\vhd0.vhdx D:\VirtualMachines\vhds\vhd1.vhdx"
        $vhdInput = Read-Host "Enter VHD/VHDX file paths"
        Set-Content -Path $default_vhdConfigFile -Value $vhdInput -Encoding UTF8
        Write-Host "VHD paths saved to $default_vhdConfigFile"
    }
} catch {
    Write-Warning "Error reading/saving VHD file paths: $($_.Exception.Message)"
    $vhdInput = ""
}

$vhdPaths = ($vhdInput -split '\s+') |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" }

foreach ($path in $vhdPaths) {
    try {
        if (-not (Test-Path $path -PathType Leaf)) {
            Write-Warning "File does not exist: $path"
            continue
        }

        $result.MsftVHD += [ordered]@{
            DiskNumber          = 'unknown'
            UniqueId            = 'unknown'
            FriendlyName        = 'Msft Virtual Disk'
            DevType             = 'MsftVHD'
            Path                = $path
            SizeMB              = $null
            SizeGB              = $null
            PartitionStyle      = $null
            MountLabel          = [IO.Path]::GetFileNameWithoutExtension($path)
            MountStatus         = 'unknown'
            PartitionsNeedMount = @()
        }
    } catch {
        Write-Warning ("Error registering VHD {0}: {1}" -f $path, $_.Exception.Message)
    }
}

# --------------------------------------------------
# STEP 2B: Attach → show VHDX disk info
# --------------------------------------------------
Write-Host "`n=== VHDX Disk Information ==="

foreach ($vhdDev in $result.MsftVHD) {

    $path = $vhdDev.Path

    if (-not (Test-Path $path -PathType Leaf)) {
        Write-Warning "Skipping missing VHDX: $path"
        continue
    }

    Write-Host "Inspecting VHDX: $path"

    try {
        # Always detach first to avoid WSL/Hyper-V ghost attachments
        Dismount-VHD -Path $path -ErrorAction SilentlyContinue

        # Attach cleanly
        $vhd = Mount-VHD -Path $path -NoDriveLetter -Passthru -ErrorAction Stop

        # Resolve disk
        $disk = Get-Disk -Number $vhd.DiskNumber -ErrorAction Stop

        # Update metadata
        $vhdDev.DiskNumber     = $disk.Number
        $vhdDev.UniqueId       = $disk.UniqueId
        $vhdDev.FriendlyName   = $disk.FriendlyName
        $vhdDev.PartitionStyle = $disk.PartitionStyle
        $vhdDev.SizeMB         = [math]::Round($disk.Size / 1MB)
        $vhdDev.SizeGB         = [math]::Round($disk.Size / 1GB, 2)

        Show-DiskInfo $disk
    }
    catch {
        Write-Warning "Failed to inspect VHDX ${path}: $($_.Exception.Message)"
    }
}

# --------------------------------------------------
# STEP 2C: VHDX partition selection (with persistence)
# --------------------------------------------------
if (Test-Path $default_vhdSelectFile) {
    $vhdSelectLine = Get-Content $default_vhdSelectFile -Raw
    Write-Host "Using saved VHDX selection: $vhdSelectLine"
}
else {
    Write-Host ""
    Write-Host "Select VHDX partitions to mount."
    Write-Host "Format: DiskNumber[partition1,partition2,...]"
    Write-Host "Example: 3[1,3] 5[2,4]"
    $vhdSelectLine = Read-Host "Enter VHDX selection"
    Set-Content -Path $default_vhdSelectFile -Value $vhdSelectLine -Encoding UTF8
    Write-Host "Selection saved to $default_vhdSelectFile"
}

$vhdTokens = $vhdSelectLine -split '\s+'

foreach ($token in $vhdTokens) {
    if ($token -match '^(\d+)\[(.*?)\]$') {

        $diskNum = [int]$matches[1]
        $parts   = @()

        if ($matches[2]) {
            foreach ($p in ($matches[2] -split ',')) {
                if ($p -match '^\d+$') { $parts += [int]$p }
            }
        }

        $dev = $result.MsftVHD | Where-Object { $_.DiskNumber -eq $diskNum }

        if (-not $dev) {
            Write-Warning "No VHDX device found with DiskNumber $diskNum"
            continue
        }

        $dev.PartitionsNeedMount = $parts
        $dev.MountStatus         = 'unknown'
    }
}

# --------------------------------------------------
# Write JSON
# --------------------------------------------------
try {
    $result | ConvertTo-Json -Depth 6 | Set-Content -Path ".\devices.json" -Encoding UTF8
    Write-Host "`nDevices.json generated successfully."
} catch {
    Write-Warning "Failed to write devices.json: $($_.Exception.Message)"
}