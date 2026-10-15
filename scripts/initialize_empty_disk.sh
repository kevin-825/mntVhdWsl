#!/usr/bin/env bash

# ==============================================================================
# Script Name: initialize_empty_disk.sh
# Description: Finds a disk by Serial Number, creates a GPT partition table, 
#              and formats the entire disk with an ext4 filesystem.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status, 
# and treat unset variables as an error.
set -euo pipefail
source scripts/get_device_by_serial.sh

# ------------------------------------------------------------------------------
# Function: format_disk_gpt_ext4
# Input: Device path
# Description: Applies GPT partition table and creates an ext4 filesystem.
# ------------------------------------------------------------------------------
format_disk_gpt_ext4() {
    local dev_path="$1"
    local part_path=""

    # Determine partition naming convention (e.g., /dev/sdb1 vs /dev/nvme0n1p1)
    if [[ "$dev_path" =~ nvme[0-9]n[0-9]$ ]]; then
        part_path="${dev_path}p1"
    else
        part_path="${dev_path}1"
    fi

    echo "==> Target disk identified: $dev_path"
    echo "==> Wiping existing signatures and setting GPT partition table..."
    sudo wipefs -a "$dev_path"
    sudo parted -s "$dev_path" mklabel gpt

    echo "==> Creating primary ext4 partition using the whole disk space..."
    sudo parted -s "$dev_path" mkpart primary ext4 0% 100%
    
    # Inform kernel of partition table changes
    sudo partprobe "$dev_path"

    # Explicitly wait until the partition node appears (with a timeout safety net)
    local timeout=10
    while [ ! -b "$part_path" ] && [ $timeout -gt 0 ]; do
        sleep 0.5
        timeout=$((timeout - 1))
    done
    # Check if we timed out
    if [ ! -b "$part_path" ]; then
        echo "Error: Partition $part_path did not appear in time." >&2
        return 1
    fi

    echo "==> Formatting $part_path with ext4 filesystem..."
    sudo mkfs.ext4 -F "$part_path"

    echo "Success: Disk '$dev_path' successfully initialized with GPT and formatted with ext4 on '$part_path'."
}

# ------------------------------------------------------------------------------
# Main Execution Routine
# ------------------------------------------------------------------------------
main() {
    local serial_input="${1:-}"
    local devType="${2:-}"
    log_debug ">>>>> Inputed args:"
    log_debug "serial_input:$serial_input"
    log_debug "devType:$devType"
    if [ -z "$serial_input" ]; then
        echo "Usage: $0 <DiskSerialNumber>"
        exit 1
    fi

    # Ensure script is run with root privileges or sudo capability
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        echo "Error: This script requires root privileges to initialize disks." >&2
        exit 1
    fi

    echo "Searching for disk with Serial Number: $serial_input..."
    normalized_serial=$(normalize_disk_identifier "$serial_input" "$devType") 
    log_debug "normalized_serial: $normalized_serial "
    local target_device 
    target_device=$(get_device_by_serial "$normalized_serial")

    validate_disk "$target_device"

    # Check if any partitions on this device are currently mounted
    if lsblk -no MOUNTPOINTS "$dev_path" | grep -q '[a-zA-Z0-9]'; then
        echo "Error: Device '$dev_path' or its partitions have active mounts. Unmount them first." >&2
        return 1
    fi

    format_disk_gpt_ext4 "$target_device"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi