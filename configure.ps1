#requires -Version 5.1

# --------------------------------------------------
# Helper: Disk & Partition Inspection
# --------------------------------------------------
function Get-DiskAndPartitionInfo {
    param ($Disk)
    
    $rows = @()
    try {
        $parts = Get-Partition -DiskNumber $Disk.Number -ErrorAction Stop
        foreach ($p in $parts) {
            $vol = Get-Volume -Partition $p -ErrorAction SilentlyContinue
            $rows += [PSCustomObject]@{
                PartitionN  = if ($p.PartitionNumber) { $p.PartitionNumber } else { 'unknown' }
                DriveLetter = if ($vol.DriveLetter) { $vol.DriveLetter } else { 'unknown' }
                Label       = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { 'unknown' }
                FsType      = if ($vol.FileSystem) { $vol.FileSystem } else { 'unknown' }
            }
        }
    } catch { }

    return $rows
}

function Show-DiskDisplay {
    param ($Disk, $PartitionRows)
    
    Write-Host ("DiskNumber:{0}  FriendlyName:`"{1}`"  UniqueID:{2}" -f $Disk.Number, $Disk.FriendlyName, $Disk.UniqueId)
    $indent = "`t`t`t"
    
    if ($PartitionRows) {
        $table = $PartitionRows | Format-Table -AutoSize | Out-String
        $table -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Host ($indent + $_) }
    } else {
        Write-Host ($indent + "PartitionN DriveLetter Label FsType")
        Write-Host ($indent + "---------- ----------- ----- ------")
        Write-Host ($indent + "unknown    unknown     unknown unknown")
    }
    Write-Host ""
}

# --------------------------------------------------
# Core Logic Modules
# --------------------------------------------------

function Get-PhysicalInventory {
    param ($ConfigFile)
    
    $disks = Get-Disk | Where-Object BusType -ne 'File Backed Virtual' | Sort-Object Number
    Write-Host "`n=== Physical Disks ==="
    foreach ($d in $disks) {
        $info = Get-DiskAndPartitionInfo -Disk $d
        Show-DiskDisplay -Disk $d -PartitionRows $info
    }

    $inputLine = ""
    if (Test-Path $ConfigFile) {
        $inputLine = Get-Content $ConfigFile -Raw
        Write-Host "Using saved physical disk selection: $inputLine"
    } else {
        $inputLine = Read-Host "`nSelect physical devices (e.g. 6[1,2] 1[])"
        $inputLine | Set-Content -Path $ConfigFile -Encoding UTF8
    }

    $inventory = @()
    foreach ($token in ($inputLine -split '\s+')) {
        if ($token -match '^(\d+)\[(.*?)\]$') {
            $diskNum = [int]$matches[1]
            
            # Create a clean array of integers
            [int[]]$parts = @()
            if ($matches[2]) { 
                $parts = $matches[2] -split ',' | ForEach-Object { [int]$_.Trim() } 
            }

            try {
                $disk = Get-Disk -Number $diskNum -ErrorAction Stop
                $devType = if ($disk.FriendlyName -match 'RAMDisk') { 'PhysicalRamDisk' } else { 'PhysicalHardDisk' }
                
                $inventory += [ordered]@{
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
                    # Cast explicitly to array to ensure JSON format [1,2] or []
                    PartitionsNeedMount = @($parts)
                }
            } catch { Write-Warning "Disk $diskNum not found." }
        }
    }
    return $inventory
}

function Get-VhdInventory {
    param ($PathConfig, $SelectConfig)

    $vhdInput = ""
    if (Test-Path $PathConfig) {
        $vhdInput = Get-Content $PathConfig -Raw
    } else {
        $vhdInput = Read-Host "`nEnter VHDX paths"
        $vhdInput | Set-Content -Path $PathConfig -Encoding UTF8
    }

    $vhdResults = @()
    $paths = $vhdInput -split '\s+' | Where-Object { $_ }

    Write-Host "`n=== VHDX Disk Information ==="
    foreach ($path in $paths) {
        if (-not (Test-Path $path)) { continue }
        try {
            Dismount-VHD -Path $path -ErrorAction SilentlyContinue
            $vhd = Mount-VHD -Path $path -NoDriveLetter -Passthru
            $disk = Get-Disk -Number $vhd.DiskNumber
            Show-DiskDisplay -Disk $disk -PartitionRows (Get-DiskAndPartitionInfo $disk)

            $vhdResults += [ordered]@{
                DiskNumber          = $disk.Number
                UniqueId            = $disk.UniqueId
                FriendlyName        = $disk.FriendlyName
                DevType             = 'MsftVHD'
                Path                = $path
                SizeMB              = [math]::Round($disk.Size / 1MB)
                SizeGB              = [math]::Round($disk.Size / 1GB, 2)
                PartitionStyle      = $disk.PartitionStyle
                MountLabel          = [IO.Path]::GetFileNameWithoutExtension($path)
                MountStatus         = 'unknown'
                PartitionsNeedMount = @() # Correct empty array initialization
            }
        } catch { Write-Warning "Failed to inspect VHDX: $path" }
    }

    $vhdSelectLine = ""
    if (Test-Path $SelectConfig) {
        $vhdSelectLine = Get-Content $SelectConfig -Raw
    } else {
        $vhdSelectLine = Read-Host "`nSelect VHDX partitions (e.g. 3[1,3])"
        $vhdSelectLine | Set-Content -Path $SelectConfig -Encoding UTF8
    }

    foreach ($token in ($vhdSelectLine -split '\s+')) {
        if ($token -match '^(\d+)\[(.*?)\]$') {
            $dNum = [int]$matches[1]
            [int[]]$parts = @()
            if ($matches[2]) {
                $parts = $matches[2] -split ',' | ForEach-Object { [int]$_.Trim() }
            }
            $dev = $vhdResults | Where-Object { $_.DiskNumber -eq $dNum }
            if ($dev) { 
                $dev.PartitionsNeedMount = @($parts)
            }
        }
    }
    return $vhdResults
}

# --------------------------------------------------
# Main Execution
# --------------------------------------------------
function main {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
        Write-Warning "Relaunching as Admin..."
        Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }

    $paths = @{
        PhysConfig   = Join-Path $PSScriptRoot "selected_physical_disks.txt"
        VhdFiles     = Join-Path $PSScriptRoot "vhdx_file_list.txt"
        VhdConfig = Join-Path $PSScriptRoot "selected_vhdx_files.txt"
        OutputJson   = Join-Path $PSScriptRoot "devices.json"
    }

    $physical = Get-PhysicalInventory -ConfigFile $paths.PhysConfig
    $vhd      = Get-VhdInventory -PathConfig $paths.VhdFiles -SelectConfig $paths.VhdConfig

    $result = @{
        Physical = $physical
        MsftVHD  = $vhd
    }

    $result | ConvertTo-Json -Depth 6 | Set-Content -Path $paths.OutputJson -Encoding UTF8
    Write-Host "`nDevices.json generated successfully."
}

if ($MyInvocation.InvocationName -ne '.') { main }