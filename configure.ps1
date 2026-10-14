#requires -Version 5.1

# --------------------------------------------------
# Helper: Disk & Partition Inspection
# --------------------------------------------------

$modulePath = Join-Path $PSScriptRoot "DiskTools.psm1"
Import-Module $modulePath -Force

function Get-DiskAndPartitionInfo {
    param ($Disk)
    
    $rows = @()
    try {
        $parts = Get-Partition -DiskNumber $Disk.Number -ErrorAction Stop
        foreach ($p in $parts) {
            $vol = Get-Volume -Partition $p -ErrorAction SilentlyContinue
            $rows += [PSCustomObject]@{
                "PartNum"   = $p.PartitionNumber
                "DrvLtr"    = if ($p.DriveLetter) { $p.DriveLetter } else { "-" }
                "Size  "    = FormatDiskSize -disk $p
                "Label     "= if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "" }
                "FsType"    = $vol.FileSystem
                "Info"      = $p.Type
            }
        }
    } catch { }

    return $rows
}

function Show-DiskDisplay {
    param ($disk, $PartitionRows)
    
    $partCount = @($partitions).Count
    $diskSize = FormatDiskSize -disk $disk
    $status = $disk.OperationalStatus
    $busType = if ($disk.BusType) { $disk.BusType } else { "Unknown" }

    Write-Host "DiskNum:$($disk.Number)  DiskName:`"$($disk.FriendlyName)`"" -ForegroundColor Cyan
    Write-Host "SerialNumber:$($disk.SerialNumber)"
    Write-Host "DiskSize: $diskSize  |  Bus: $busType  |  status: $status"
    Write-Host "PartitionStyle:$($disk.PartitionStyle)  |  PartCount:$partCount"
    #$indent = "`t"
    
    if ($PartitionRows) {
        $table = $PartitionRows | Format-Table -AutoSize | Out-String
        $table | Where-Object { $_.Trim() } | ForEach-Object { Write-Host ($indent + $_) }
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
    
    $inputLine = ""
    if (Test-Path $ConfigFile) {
        $inputLine = Get-Content $ConfigFile -Raw
        Write-Host "Using saved physical disk selection: $inputLine"
    } else {
        $inputLine = Read-Host "`nSelect physical devices and it's partitions (e.g. 6[1,2] 1[])"
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

            $dev = Get-Disk -Number $diskNum -ErrorAction Stop
            $ret=CheckInitializeEmptyDisk $dev -ErrorAction Stop
            #if($ret -ne 0) {exit 1}

            try {
                $disk = Get-Disk -Number $diskNum -ErrorAction Stop
                $devType = if ($disk.FriendlyName -match 'RAMDisk') { 'RamDisk' } else { 'PhysicalHardDisk' }

                $inventory += [ordered]@{
                    DiskNumber          = $diskNum
                    SerialNumber        = $disk.SerialNumber
                    FriendlyName        = $disk.FriendlyName
                    DevType             = $devType
                    Path                = $null
                    Size                = FormatDiskSize -disk $
                    PartitionTotalCnt   = @(Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue).Count
                    PartitionStyle      = $disk.PartitionStyle
                    MountLabel          = if ($devType -eq 'RamDisk') { "ramdisk$diskNum" } else { "disk$diskNum" }
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
    param ($fileListConfig, $SelectConfig)

    $vhdInput = Get-Content $fileListConfig -Raw
    if (-not $vhdInput) {
        $vhdInput = Read-Host "`nEnter VHDX paths"
        $vhdInput | Set-Content -Path $fileListConfig -Encoding UTF8
    }

    $paths = $vhdInput -split '\s+' | Where-Object { $_ }
    foreach ($path in $paths) {
        if (-not (Test-Path $path)) { continue }
        Dismount-VHD -Path $path -ErrorAction SilentlyContinue
        $vhd = Mount-VHD -Path $path -NoDriveLetter -Passthru
        Show-VhdDiskSummary -Path $vhd.Path
    }



    if (Test-Path $SelectConfig) {
        $inputLine = Get-Content $SelectConfig -Raw
        Write-Host "Using saved Virtual Disk VHDX selection: $inputLine"
    } else {
        $inputLine = Read-Host "`nSelect virtual devices and it's partitions (e.g. 6[1,2] 1[])"
        $outputLines = @()
        foreach ($token in ($inputLine -split '\s+')) {
            if ($token -match '^(\d+)\[(.*?)\]$') {
                $diskNum = $matches[1]
                $Path=(Get-VHD -DiskNumber $diskNum).Path
                Get-Disk -Number $diskNum -ErrorAction Stop
                # Create a clean array of integers
                [int[]]$parts = @()
                if ($matches[2]) { 
                    $parts = $matches[2] -split ',' | ForEach-Object { [int]$_.Trim() } 
                }
                Write-Host " >>>>>>> path: $path $outputline    matches[2]: $matches[2]  "

                $singleLine = "$($Path)[$($matches[2])]"
                Write-Host " singleLine: $singleLine"
                $outputLines += $singleLine
            }
        }
        $outputlines | Set-Content -Path $SelectConfig -Encoding UTF8
        $inputLine = Get-Content $SelectConfig -Raw
    }

    $vhdResults = @()
    
    Write-Host "`n=== VHDX Disk Information ===  inputLine:$inputLine"
    foreach ( $line in ($inputLine -split '\s+')) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        #if (-not (Test-Path $path)) { continue }
        #$line -match '^(?<path>.+?)\[(?<parts>.*)\]$'
        $cleanLine = $line.Trim()
        Write-Host "++++> cleanLine : $cleanLine +++====="
        if ($cleanLine -match '^(?<path>.+?)\[(?<parts>.*)\]$') {
            $path = $matches['path'].Trim()

            # Create a clean array of integers
            [int[]]$parts = @()
            if ($matches['parts']) { 
                $parts = $matches['parts'] -split ',' | ForEach-Object { [int]$_.Trim() } 
            }
            
            Dismount-VHD -Path $path -ErrorAction Stop
            $vhd = Mount-VHD -Path $path -NoDriveLetter -Passthru
            $dev = Get-Disk -Number $($vhd.DiskNumber) -ErrorAction Stop
            Write-Host "+++++++++++ path:$path DiskNumber:$($vhd.DiskNumber) BusType:$($dev.BusType) "
            $ret=CheckInitializeEmptyDisk $dev -ErrorAction Stop
            Write-Host "+++++++++++ path:$path DiskNumber:$($vhd.DiskNumber) BusType:$($dev.BusType) "
            #if($ret -ne 0) {exit 1}

            try {
                $disk = Get-Disk -Number $vhd.DiskNumber


                $vhdResults += [ordered]@{
                    DiskNumber          = $disk.Number
                    SerialNumber        = $vhd.DiskIdentifier
                    FriendlyName        = $disk.FriendlyName
                    DevType             = 'MsftVHD'
                    Path                = $path
                    Size                = FormatDiskSize -disk $vhd
                    PartitionStyle      = $disk.PartitionStyle
                    PartitionTotalCnt   = @(Get-Partition -DiskNumber $vhd.DiskNumber -ErrorAction SilentlyContinue).Count
                    MountLabel          = [IO.Path]::GetFileNameWithoutExtension($path)
                    MountStatus         = 'unknown'
                    PartitionsNeedMount = @($parts)
                }
            } catch { Write-Warning "Failed to inspect VHDX: $path" }
        } else {
            Write-Error "Wrong farmat in the $SelectConfig file: $line"
            exit 1
        }
    }
    return $vhdResults
}

# --------------------------------------------------
# Main Execution
# --------------------------------------------------
function main {
    Assert-Administrator -ScriptPath $PSCommandPath

    $paths = @{
        VhdFiles     = Join-Path $PSScriptRoot "vhdx_file_list.txt"
        VhdConfig    = Join-Path $PSScriptRoot "selected_vhdx_files.txt"
        PhysConfig   = Join-Path $PSScriptRoot "selected_physical_disks.txt"
        OutputJson   = Join-Path $PSScriptRoot "devices.json"
    }
    wsl --shutdown
    BringAlldiskOnline
    #Remove-Item $paths.VhdConfig -ErrorAction SilentlyContinue
    Show-AllDiskSummary 
    $physical = Get-PhysicalInventory -ConfigFile $paths.PhysConfig

    #Show-AllVHDSummary -VHDfileListConfigFilePath $paths.VhdFiles
    $vhd      = Get-VhdInventory -fileListConfig $paths.VhdFiles -SelectConfig $paths.VhdConfig

    $result = @{
        Physical = $physical
        MsftVHD  = $vhd
    }

    $result | ConvertTo-Json -Depth 6 | Set-Content -Path $paths.OutputJson -Encoding UTF8
    Write-Host "`nDevices.json generated successfully."
}

if ($MyInvocation.InvocationName -ne '.') { main }