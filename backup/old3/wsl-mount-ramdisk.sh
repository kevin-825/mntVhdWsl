#!/bin/bash

set -euo pipefail

MOUNT_BASE="/mnt/wsl"

# Scan for partitions labeled RamDiskN
lsblk -rno NAME,LABEL,TYPE | while read -r name label type; do
    [[ "$type" != "part" ]] && continue
    [[ ! "$label" =~ ^RamDisk[0-9]+$ ]] && continue

    part="/dev/$name"
    index="${label//[!0-9]/}"          # RamDisk0 → 0
    new_label="ramdisk${index}"
    mount_point="${MOUNT_BASE}/${new_label}"

    # Parent disk (e.g., sdh1 → sdh)
    parent_disk=$(lsblk -no PKNAME "$part")
    disk="/dev/$parent_disk"

    # Read metadata only for the matched device
    info=$(udevadm info --query=property --name="$disk")
    vendor=$(echo "$info" | grep "^ID_VENDOR=" | cut -d= -f2- || echo "UNKNOWN")
    model=$(echo "$info" | grep "^ID_MODEL="  | cut -d= -f2- || echo "UNKNOWN")

    # Print the current UUID before formatting



    echo "Matched RAM disk:"
    echo "  Disk:      $disk"
    echo "  Partition: $part"
    echo "  Vendor:    $vendor"
    echo "  Model:     $model"
    echo "  Label:     $label"
    echo "  New label: $new_label"
    echo "  Mount to:  $mount_point"
    echo


    echo "→ Wiping signatures on $disk..."
    sudo wipefs -a "$disk"

    echo "→ Formatting WHOLE DISK as ext4..."
    sudo mkfs.ext4 -F -L "$new_label" "$disk"


    echo "→ Mounting..."
    sudo mkdir -p "$mount_point"
    sudo mount "$disk" "$mount_point"

    echo "→ RAM disk initialized and mounted at $mount_point"
    echo "→ Setting ownership to user..."
    sudo chown -R "$USER:$USER" "$mount_point"
    echo

done



create_link() {
    local src="$1"
    local dst="$2"

    # If the link already exists and points to the right place, skip
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$src" ]; then
        return
    fi

    # If something else exists at the target, remove it
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        rm -rf "$dst"
    fi

    ln -s "$src" "$dst"
}

create_link /mnt/wsl/ramdisk0        ~/rd0
create_link /mnt/wsl/disk1_32g_p1    ~/d1
create_link /mnt/wsl/disk2_110g_p1   ~/d2

find $MOUNT_BASE -mindepth 2 -maxdepth 2
