function Show-DetailedDiskSummary {
    [CmdletBinding()]
    param()

    process {
        $disks = Get-Disk | Sort-Object Number

        foreach ($disk in $disks) {
            $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
            $partCount = if ($partitions) { @($partitions).Count } else { 0 }
            $diskSizeGB = [Math]::Round($disk.Size / 1GB, 2)

            # Print Disk Metadata
            Write-Host "DiskNum:$($disk.Number)  DiskName:`"$($disk.FriendlyName)`"" -ForegroundColor Cyan
            Write-Host "UniqueID:$($disk.UniqueId)"
            Write-Host "DiskSize: $diskSizeGB GB"
            Write-Host "PartitionStyle:$($disk.PartitionStyle)"
            Write-Host "PartCount:$partCount"

            if ($partCount -gt 0) {
                # Print Table Header with indentation
                Write-Host "`tPartNum`tDriveLetter`tLabel`t`tFsType"
                Write-Host "`t-------`t------------`t-------`t---------"

                $partitions | ForEach-Object {
                    $p =$_
                    $volume =$p | Get-Volume -ErrorAction SilentlyContinue
                    $pNum   =$p.PartitionNumber
                    $letter = if ($p.DriveLetter) { "$($p.DriveLetter)" } else { "-" }
                    $label  = if ($volume.FileSystemLabel) {$volume.FileSystemLabel } else { "" }
                    $fsType = if ($volume.FileSystem) {$volume.FileSystem } else { "Unformatted" }

                    # Print Partition Row
                    Write-Host "`t$pNum`t`t$letter`t`t$label`t`t$fsType"
                }
            } else {
                Write-Host "`t(No partitions found)" -ForegroundColor DarkGray
            }
            
            Write-Host "" # Blank line between disks
        }
    }
}

# Run the function
Show-DetailedDiskSummary