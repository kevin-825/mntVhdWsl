Import-Module (Join-Path $PSScriptRoot "DiskTools.psm1") -Force

function Get-VhdPathsFromFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PathConfig
    )

    if (-not (Test-Path $PathConfig)) {
        throw "VHD configuration file not found: $PathConfig"
    }

    $vhdInput = Get-Content $PathConfig -Raw
    $rawTokens = $vhdInput -split '\s+' | Where-Object { $_ -and $_.Trim() }

    if (-not $rawTokens -or $rawTokens.Count -eq 0) {
        throw "VHD configuration file is empty: $PathConfig"
    }

    $validPaths = @()
    foreach ($token in $rawTokens) {
        # Clean up any surrounding quotes
        $cleanPath = $token.Trim('"''')
        
        # Stop immediately if any file path is missing
        if (-not (Test-Path $cleanPath)) {
            throw "VHD file path specified in config does not exist: $cleanPath"
        }
        
        $validPaths += $cleanPath
    }

    return ,$validPaths
}


function Show-VhdSummaryFromFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PathConfig
    )

    # Load paths using our dedicated data-loading function
    $vhdPaths = Get-VhdPathsFromFile -PathConfig $PathConfig

    if (-not $vhdPaths -or $vhdPaths.Count -eq 0) {
        Write-Warning "No valid VHD paths found to process in: $PathConfig"
        return
    }

    Write-Host "=== Processing VHD List from: $PathConfig ===" -ForegroundColor Cyan
    foreach ($path in $vhdPaths) {
        Show-VhdSummary -Path $path
    }
}



function Show-VhdSummary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "VHD/VHDX file not found: $Path"
        return
    }

    try {
        # Check if the VHD is already mounted
        $vhdInfo = Get-VHD -Path $Path -ErrorAction SilentlyContinue
        $diskNum = $null

        if (-not $vhdInfo -or $vhdInfo.Attached -eq $false) {
            Write-Verbose "Mounting VHD: $Path"
            $mountedVhd = Mount-VHD -Path $Path -NoDriveLetter -Passthru -ErrorAction Stop
            $diskNum = $mountedVhd.DiskNumber
        } else {
            $diskNum = $vhdInfo.DiskNumber
        }

        if ($null -ne $diskNum) {
            $disk = Get-Disk -Number $diskNum -ErrorAction Stop
            Write-Host "=== VHDX File: $Path ===" -ForegroundColor Magenta
            Show-DiskSummary -Disk $disk
        } else {
            Write-Warning "Could not determine disk number for VHD: $Path"
        }
    } catch {
        Write-Warning "Failed to process VHDX file '$Path': $_"
    }
}

function Show-AllVhdSummary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$Paths,

        [Parameter(Mandatory = $false)]
        [string]$Directory
    )

    $targetPaths = @()

    if ($Paths) {
        $targetPaths += $Paths
    }

    if ($Directory -and (Test-Path $Directory)) {
        $foundFiles = Get-ChildItem -Path $Directory -Include *.vhd, *.vhdx -Recurse -File | Select-Object -ExpandProperty FullName
        $targetPaths += $foundFiles
    }

    if (-not $targetPaths -or $targetPaths.Count -eq 0) {
        Write-Warning "No VHD/VHDX paths or directory provided."
        return
    }

    foreach ($vhdPath in $targetPaths) {
        Show-VhdSummary -Path $vhdPath
    }
}