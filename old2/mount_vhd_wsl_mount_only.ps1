param (
    [Parameter(Mandatory=$true)]
    [string]$Distro,

    [Parameter(Mandatory=$true)]
    [string[]]$VhdPaths
)

$mountedVhds = @()
$count = 0

foreach ($vhdPath in $VhdPaths) {
    $driveName = "vhd$count"
    $vhdFull = "\\?\$vhdPath"

    # Unmount if already mounted
    wsl --unmount "$vhdFull" 2>$null

	echo vhdFull:$vhdFull
    # Mount the VHD with --bare
    wsl --mount --vhd "$vhdFull" --name $driveName



    # Create symbolic link in WSL home
	$linkCmd = @"
set -e && ls /mnt/wsl/
`[ -e /home/`$(whoami)/$driveName `] && echo /home/`$(whoami)/$driveName esxits!!!! deleting !!! && rm /home/`$(whoami)/$driveName
ln -s /mnt/wsl/$driveName /home/`$(whoami)/$driveName && echo link created!!!!!!
"@ -replace "`r", ""
	
	echo ++++
	echo $linkCmd
	echo ++++
	wsl -d $Distro -- bash -c "`"$linkCmd`""


    $mountedVhds += $vhdFull
    $count++
}

Write-Host "✅ All VHD/VHDX files mounted."

## Start WSL session
#wsl -d $Distro bash -c "cd ~ && exec bash"
#
## Terminate WSL session
#wsl -t $Distro
#
## Unmount all VHDs
#foreach ($vhd in $mountedVhds) {
#    wsl --unmount "$vhd"
#}
#
#Write-Host "✅ All VHD/VHDX files mounted."

