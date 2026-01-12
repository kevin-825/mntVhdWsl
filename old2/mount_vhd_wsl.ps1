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



    # Create temp bash script
#$scriptContent = @"
#
#NEW_DISK="`$USER"
#echo New disk detected: /dev/`$NEW_DISK
#echo `$USER
#
#echo "USER is: `$USER"
#env | grep USER
#"@ -replace "`r", ""
#
#
#
#
#	echo "done\n"
#	echo $scriptContent
#    # Run the script inside WSL
#    wsl -d $Distro -- bash -c "`"$scriptContent`""
#	echo "done2\n"



# Create symbolic link in WSL home
	$linkCmd = @"
set -e && ls /mnt/wsl/
`[ -e /home/`$(whoami)/$driveName `] && echo /home/`$(whoami)/$driveName esxits!!!!
ln -s /mnt/wsl/$driveName /home/`$(whoami)/$driveName
"@ -replace "`r", ""
	
	echo ++++
	echo $linkCmd
	echo ++++
	wsl -d $Distro -- bash -c "`"$linkCmd`""


    $mountedVhds += $vhdFull
    $count++
}

# Start WSL session
wsl -d $Distro bash -c "cd ~ && exec bash"

# Terminate WSL session
wsl -t $Distro

# Unmount all VHDs
foreach ($vhd in $mountedVhds) {
    wsl --unmount "$vhd"
}

Write-Host "✅ All VHD/VHDX files unmounted."

