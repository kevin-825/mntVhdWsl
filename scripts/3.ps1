



function Show-DiskSummaryAutoAligned {
    [CmdletBinding()]
    param()

    process {
        $disks = Get-Disk | Sort-Object Number

        foreach ($disk in $disks) {
            $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
            $partCount = @($partitions).Count
            $diskSizeGB = [Math]::Round($disk.Size / 1GB, 2)
            $status = $disk.OperationalStatus
            $busType = if ($disk.BusType) { $disk.BusType } else { "Unknown" }

            # Print Disk Metadata
            Write-Host "DiskNum:$($disk.Number)  DiskName:`"$($disk.FriendlyName)`"" -ForegroundColor Cyan
            Write-Host "UniqueID:$($disk.UniqueId)"
            Write-Host "DiskSize: $diskSizeGB GB  |  Bus: $busType  |  status: $status"
            Write-Host "PartitionStyle:$($disk.PartitionStyle)  |  PartCount:$partCount" -NoNewline

            if ($partCount -gt 0) {
                Write-Host ""
                
                # Build custom objects so Format-Table handles alignment automatically
                $partitionData = foreach ($p in $partitions) {
                    $volume = $p | Get-Volume -ErrorAction SilentlyContinue
                    # Dynamic Size Formatting (GB if >= 1GB, else MB)
                    $formattedSize = if ($p.Size -ge 1TB) {
                        "{0:N0} TB" -f ($p.Size / 1TB)
                    } elseif ($p.Size -ge 1GB) {
                        "{0:N0} GB" -f ($p.Size / 1GB)
                    } else {
                        "{0} MB" -f [Math]::Round($p.Size / 1MB)
                    }

                    [PSCustomObject]@{
                        "PartNum"   = $p.PartitionNumber
                        "DrvLtr"    = if ($p.DriveLetter) { $p.DriveLetter } else { "-" }
                        "Size  "    = $formattedSize
                        "Label     "= if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { "" }
                        "FsType"    = $volume.FileSystem
                        "Info"      = $p.Type
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
    }
}

# --------------------------------------------------
# Main Execution
# --------------------------------------------------
function main {
    Relaunch_As_Admin
    bringAlldiskOnline
    Show-DiskSummaryAutoAligned
    pause
}

if ($MyInvocation.InvocationName -ne '.') { main }