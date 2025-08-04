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
$scriptContent = @"
NEW_DISK="`$(lsblk -nr -o NAME,TYPE | awk '`$2=="disk" {print `$1}' | sort | tail -n1)"
echo New disk detected: /dev/`$NEW_DISK
PART="`$(lsblk -nr -o NAME,TYPE | awk -v disk=`"`$NEW_DISK" '`$2=="part" && `$1 ~ "^"disk {print `$1}' | head -n1)"
echo "PART is: `$PART"
if [ -n "`$PART" ]; then
    echo "Mounting /dev/`$PART to /mnt/wsl/$driveName"
    sudo mkdir -p /mnt/wsl/`$driveName
    sudo mount /dev/`$PART /mnt/wsl/$driveName
else
    echo "No partition found for disk `$NEW_DISK. Skipping mount."
fi
"@ -replace "`r", ""




	echo "done\n"
    # Run the script inside WSL
    wsl -d $Distro -- bash -c "`"$scriptContent`""
	echo "done2\n"
    # Create symbolic link in WSL home

	$linkCmd = @"
set -e && ls /mnt/wsl/
`[ ! -e /home/`$(whoami)/$driveName ] && ln -s /mnt/wsl/$driveName /home/`$(whoami)/$driveName
"@ -replace "`r", ""
	
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
	echo vhd:$vhd
    wsl --unmount "$vhd"
}

Write-Host "✅ All VHD/VHDX files unmounted."
