# DiskTools.psm1
function Assert-Administrator {
    param (
        # Accept the calling script's path explicitly
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")

    if (-not $isAdmin) {
        Write-Warning "Relaunching script as Administrator..."
        Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -Verb RunAs
        exit
    }
}


function BringAlldiskOnline {
    [CmdletBinding()]
    param()

    process {
        $disks = Get-Disk | Sort-Object Number
        foreach ($disk in $disks) {
            if ($disk.IsOffline) {
                Write-Host "Disk $($disk.Number) is offline. Bringing it online..." -ForegroundColor Yellow
                Set-Disk -Number $disk.Number -IsOffline $false
            }
        }
    }
}

function FormatDiskSize {
    param ($disk)
    if ($disk.Size -ge 1TB) {
        "{0:N0} TB" -f ($disk.Size / 1TB)
    } elseif ($disk.Size -ge 1GB) {
        "{0:N0} GB" -f ($disk.Size / 1GB)
    } else {
        "{0} MB" -f [Math]::Round($disk.Size / 1MB)
    }
}


function Show-DiskSummary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Disk
    )

    $partitions = Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue
    $partCount = @($partitions).Count
    $diskSizeGB = [Math]::Round($Disk.Size / 1GB, 2)
    $status = $Disk.OperationalStatus
    $busType = if ($Disk.BusType) { $Disk.BusType } else { "Unknown" }

    # Print Disk Metadata
    Write-Host "DiskNum:$($Disk.Number)  DiskName:`"$($Disk.FriendlyName)`"" -ForegroundColor Cyan
    Write-Host "SerialNumber:$($Disk.SerialNumber)"
    Write-Host "DiskSize: $diskSizeGB GB  |  Bus: $busType  |  status: $status"
    Write-Host "PartitionStyle:$($Disk.PartitionStyle)  |  PartCount:$partCount" -NoNewline

    if ($partCount -gt 0) {
        Write-Host ""
        
        # Build custom objects so Format-Table handles alignment automatically
        $partitionData = foreach ($p in $partitions) {
            $volume = $p | Get-Volume -ErrorAction SilentlyContinue
            
            [PSCustomObject]@{
                "PartNum"  = $p.PartitionNumber
                "DrvLtr"   = if ($p.DriveLetter) { $p.DriveLetter } else { "-" }
                "Size  "   = formatDiskSize -disk $p
                "Label    "= if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { "" }
                "FsType"   = $volume.FileSystem
                "Info"     = $p.Type
            }
        }

        # Print auto-aligned table with clean indentation
        $partitionData | Format-Table -AutoSize | Out-String | ForEach-Object {
            Write-Host "    $_" -NoNewline
        }
    } else {
        Write-Host "    (No partitions found)" -ForegroundColor DarkGray
    }
    
    Write-Host "`n" # Blank line between disks
}

function Show-VhdDiskSummary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $vhd = Get-VHD -Path $Path -ErrorAction SilentlyContinue
    if (-not $vhd) {
        Write-Warning "Could not find VHD at: $Path"
        return
    }

    $vhdSizeGB = [Math]::Round($vhd.Size / 1GB, 2)
    $vhdFileSizeGB = [Math]::Round($vhd.FileSize / 1GB, 2)

    # If attached, fetch the underlying Windows Disk object so we can use your exact partition logic
    if ($vhd.Attached -and $vhd.DiskNumber -ne $null) {
        $disk = Get-Disk -Number $vhd.DiskNumber -ErrorAction SilentlyContinue
    }

    if ($disk) {
        $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
        $partCount = @($partitions).Count
        $status = $disk.OperationalStatus

        # Print VHD & Disk Metadata matching your Show-DiskSummary style
        Write-Host "VhdPath:`"$($vhd.Path)`"" -ForegroundColor Cyan
        Write-Host "DiskNum:$($disk.Number)  |  VirtualSize: $vhdSizeGB GB  |  FileSize: $vhdFileSizeGB GB  |  Status: Attached"
        Write-Host "PartitionStyle:$($disk.PartitionStyle)  |  PartCount:$partCount" -NoNewline

        if ($partCount -gt 0) {
            Write-Host ""
            
            # Build custom objects so Format-Table handles alignment automatically
            $partitionData = foreach ($p in $partitions) {
                $volume = $p | Get-Volume -ErrorAction SilentlyContinue
                
                [PSCustomObject]@{
                    "PartNum"  = $p.PartitionNumber
                    "DrvLtr"   = if ($p.DriveLetter) { $p.DriveLetter } else { "-" }
                    "Size  "   = formatDiskSize -disk $p
                    "Label   " = if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { "" }
                    "FsType"   = $volume.FileSystem
                    "Info"     = $p.Type
                }
            }

            # Print auto-aligned table with clean indentation
            $partitionData | Format-Table -AutoSize | Out-String | ForEach-Object {
                Write-Host "    $_" -NoNewline
            }
        } else {
            Write-Host "    (No partitions found)" -ForegroundColor DarkGray
        }
    } else {
        # Detached VHD fallback summary
        Write-Host "VhdPath:`"$($vhd.Path)`"" -ForegroundColor Cyan
        Write-Host "VirtualSize: $vhdSizeGB GB  |  FileSize: $vhdFileSizeGB GB  |  Status: Detached" -ForegroundColor Yellow
        Write-Host "    (VHD is not currently attached)" -ForegroundColor DarkGray
    }
    
    Write-Host "`n" # Blank line between summaries
}


function Show-VhdDiskSummary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $vhd = Get-VHD -Path $Path -ErrorAction SilentlyContinue
    if (-not $vhd) {
        Write-Warning "Could not find VHD at: $Path"
        return
    }

    $vhdSizeGB = [Math]::Round($vhd.Size / 1GB, 2)
    $vhdFileSizeGB = [Math]::Round($vhd.FileSize / 1GB, 2)
    $disk =$null

    if ($vhd.Attached -and $vhd.DiskNumber -ne$null) {
        $disk = Get-Disk -Number $vhd.DiskNumber -ErrorAction SilentlyContinue
    }

    if ($disk) {
        $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
        $partCount = @($partitions).Count

        Write-Host "VhdPath:`"$($vhd.Path)`"" -ForegroundColor Cyan
        Write-Host "DiskNum:$($disk.Number)  |  VirtualSize: $vhdSizeGB GB  \vert{}  FileSize:$vhdFileSizeGB GB  |  Status: Attached"
        Write-Host "PartitionStyle:$($disk.PartitionStyle)  \vert{}  PartCount:$partCount" -NoNewline

        if ($partCount -gt 0) {
            Write-Host ""
            $partitionData = foreach ($p in $partitions) {
                $volume =$p | Get-Volume -ErrorAction SilentlyContinue
                [PSCustomObject]@{
                    "PartNum"  = $p.PartitionNumber
                    "DrvLtr"   = if ($p.DriveLetter) {$p.DriveLetter } else { "-" }
                    "Size  "   = formatDiskSize -disk $p
                    "Label   " = if ($volume.FileSystemLabel) {$volume.FileSystemLabel } else { "" }
                    "FsType"   = $volume.FileSystem
                    "Info"     = $p.Type
                }
            }

            $tableString =$partitionData | Format-Table -AutoSize | Out-String
            foreach ($line in ($tableString -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Write-Host "    $line"
                }
            }
        } else {
            Write-Host "    (No partitions found)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "VhdPath:`"$($vhd.Path)`"" -ForegroundColor Cyan
        Write-Host "VirtualSize: $vhdSizeGB GB  \vert{}  FileSize:$vhdFileSizeGB GB  |  Status: Detached" -ForegroundColor Yellow
        Write-Host "    (VHD is not currently attached)" -ForegroundColor DarkGray
    }
    
    Write-Host ""
}


function Show-DiskSummaryByNumber {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$DiskNumber
    )

    try {
        $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
        Show-DiskSummary -Disk $disk
    } catch {
        Write-Warning "Disk number $DiskNumber was not found or could not be accessed."
    }
}

function Show-AllDiskSummary {
    [CmdletBinding()]
    param ($VHDfileListConfigFilePath)

    $disks = Get-Disk | Sort-Object Number
    foreach ($disk in $disks) {
        Show-DiskSummary -Disk $disk
    }
}
function Show-AllVHDSummary {
    [CmdletBinding()]
    param ($VHDfileListConfigFilePath)

    $vhdInput = Get-Content $VHDfileListConfigFilePath -Raw
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
}

function De-initialize_disk_by_num {
    [CmdletBinding()]
    param ($diskNum)
    #Clear-Disk -Number 1 -RemoveData -RemoveOEM -Confirm:$false
    Clear-Disk -Number $diskNum -RemoveData -RemoveOEM -Confirm:$false

}

function Invoke-Wsl {
    param([string]$Command)
    return (& wsl.exe bash -lc "$Command" 2>$null) -join "`n"
}

# ------------------------------------------------------------
# Helper: find Linux disk node (/dev/sdX) by SerialNumber ↔ ID_SERIAL_SHORT
# ------------------------------------------------------------
function Find-LinuxDiskBySerialNumber {
    param([string]$SerialNumber)

    Write-Host "  [ramdisk] Resolving Linux disk for SerialNumber=$SerialNumber"

    $lsblkJson = Invoke-Wsl "lsblk -J -o NAME,TYPE"
    if (-not $lsblkJson) { return $null }

    $lsblk = $lsblkJson | ConvertFrom-Json

    foreach ($devNode in $lsblk.blockdevices) {
        if ($devNode.type -ne "disk") { continue }

        $name = $devNode.name
        $udevOut = Invoke-Wsl "udevadm info --query=property --name=/dev/$name | grep '^ID_SERIAL_SHORT=' || true"
        Write-Host " udevOut: $udevOut"
        if (-not $udevOut) { continue }

        $line = ($udevOut -split "`n") | Where-Object { $_ -like 'ID_SERIAL_SHORT=*' } | Select-Object -First 1
        if (-not $line) { continue }

        $short = ($line -split "=",2)[1].Trim()

        if ($short -eq $SerialNumber) {
            Write-Host "  [ramdisk] Matched SerialNumber=$SerialNumber to /dev/$name"
            return "/dev/$name"
        }
    }

    Write-Warning "  [ramdisk] No Linux disk found for SerialNumber=$SerialNumber"
    return $null
}

function Translate-WinPath2LinuxPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'Path')]
        [string[]]$WinPath
    )

    process {
        foreach ($path in $WinPath) {
            # 1. Resolve relative paths (like "." or "..\foo") to absolute Windows paths
            $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)

            # 2. Try using WSL's native 'wslpath' utility (handles custom mounts & distros perfectly)
            try {
                $linuxPath = & wsl.exe wslpath -u "$resolvedPath" 2>&1
                if ($LASTEXITCODE -eq 0 -and $linuxPath) {
                    $linuxPath.Trim()
                    continue
                }
            }
            catch {
                # Fallback to manual string conversion if wslpath encounters an issue
            }

            # 3. Pure PowerShell Fallback (C:\Foo\Bar -> /mnt/c/Foo/Bar)
            if ($resolvedPath -match '^[a-zA-Z]:') {
                $drive = $resolvedPath.Substring(0, 1).ToLower()
                $remainder = $resolvedPath.Substring(2).Replace('\', '/')
                "/mnt/$drive$remainder"
            } 
            else {
                # Generic fallback for UNC or non-standard paths
                $resolvedPath.Replace('\', '/')
            }
        }
    }
}

function CheckInitializeEmptyDisk {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]$dev
    )

    # Make the condition strict: It must be RAW/Unknown AND have 0 partitions to be considered empty
    Write-Host " PartitionStyle:$($dev.PartitionStyle)  $($dev.PartitionTotalCnt)"
    $part_cnt=@(Get-Partition -DiskNumber $($dev.diskNumber) -ErrorAction SilentlyContinue).Count
    $isUninitialized = `
        ($dev.PartitionStyle -in @('RAW', 'Unknown')) `
        -or (-not $part_cnt)
    Write-Host " PartitionStyle:$($dev.PartitionStyle)  part_cnt:$($part_cnt)  isUninitialized:$isUninitialized"
    if (-not $isUninitialized) {
        Write-Host "Disk $($dev.DiskNumber) is Normal (Not Empty) ..." -ForegroundColor Green
        return 0
    }
    
    # FIXED: Changed invalid color 'Read' to 'Red'
    Write-Host ">>>>Empty disk Found:  " -ForegroundColor Red
   
    
    if ($dev.BusType -eq "File Backed Virtual") {
        $vhd=Get-VHD -Number $($dev.DiskNumber) -ErrorAction Stop
        Show-VhdDiskSummary -Path $($vhd.Path)
        Dismount-VHD -Path $($vhd.Path) -ErrorAction SilentlyContinue
        $wsl_dev_path = "$($vhd.Path)"
        $wsl_mnt_args = "--vhd", "$($vhd.Path)"
        $SerialNumber = "$($vhd.DiskIdentifier)"
        $devType      = "MsftVHD"
    } else {
         Show-DiskSummaryByNumber -DiskNumber $($dev.DiskNumber)
        $wsl_dev_path = "\\.\PHYSICALDRIVE$($dev.DiskNumber)"
        $wsl_mnt_args = "$wsl_dev_path"
        $SerialNumber = $dev.SerialNumber
        $devType= if ($disk.FriendlyName -match 'RAMDisk') { 'RamDisk' } else { 'PhysicalHardDisk' }
    }
    Write-Host "  Initializing empty disk ... wsl_mnt_args:$wsl_mnt_args" -ForegroundColor Red

    # FIXED: Use Dismount-VHD for VHDs and wsl --unmount for physical disks
    if ($dev.BusType -eq "File Backed Virtual") {
        Dismount-VHD -Path "$wsl_dev_path" -ErrorAction SilentlyContinue
    } else {
        wsl.exe --unmount $wsl_dev_path *>&1 | Out-Null
    }
    $output=""
    try {
        # Pass variables cleanly without breaking syntax
        if ($dev.BusType -eq "File Backed Virtual") {
            wsl.exe --mount --vhd "$wsl_dev_path" --bare
        } else {
            wsl.exe --mount "$wsl_dev_path" --bare
        }
        
        # ADDED: Catch external command failures (PowerShell doesn't throw on non-zero exit codes automatically)
        if ($LASTEXITCODE -ne 0) {
            throw "wsl.exe --mount failed with exit code $LASTEXITCODE"
        }
        # Get the WSL-compatible path of your current Windows project directory
        # FIXED: Use $PWD.ProviderPath to prevent backslash stripping
        $wslProjectDir = Translate-WinPath2LinuxPath $PSScriptRoot
        Write-Host "wslProjectDir: $wslProjectDir"

        # Cd into the project directory first, then run the script
        $output = wsl.exe -u root bash -lc "cd '$wslProjectDir' && ./scripts/initialize_empty_disk.sh $SerialNumber $devType"

        if ($LASTEXITCODE -ne 0) {
            throw "initialize_empty_disk.sh failed with exit code $LASTEXITCODE"
        }
        wsl.exe --unmount $wsl_dev_path
        if ($dev.BusType -eq "File Backed Virtual") { Mount-VHD -Path $wsl_dev_path -NoDriveLetter -Passthru}


        foreach ($line in $output) {
            Write-Host "$line"
        }
        
        Write-Warning " >>>Done Initilizing Empty disk! "
        
    } catch {
        # ADDED: Granular tracing showing exact line number and error message
        Write-Warning "Failed at line $($_.InvocationInfo.ScriptLineNumber): $_"
        foreach ($line in $output) {
            Write-Host "$line"
        }
        
        wsl.exe --unmount $wsl_dev_path
        if ($dev.BusType -eq "File Backed Virtual") { Mount-VHD -Path $wsl_dev_path -NoDriveLetter -Passthru}
        exit 1
    }
    
}
