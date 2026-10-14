#!/usr/bin/env bash

# ==============================================================================
# Script Name: initialize_empty_disk.sh
# Description: Finds a disk by Serial Number, creates a GPT partition table, 
#              and formats the entire disk with an ext4 filesystem.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status, 
# and treat unset variables as an error.
set -euo pipefail
DEBUG=1
log_debug() {
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

normalize_disk_identifier() {
    local serial_input="${1:-}"
    local devType="${2:-}"
    
    if [ "$devType" = "MsftVHD" ]; then
        # For VHDX files, strip hyphens, convert to lowercase, 
        # and extract the trailing signature matching Linux udev properties
        local clean_guid
        clean_guid=$(echo "$serial_input" | tr -d '-' | tr '[:upper:]' '[:lower:]')
        echo "${clean_guid: -12}"
    else
        # For physical disks, clean up standard serial numbers
        echo "$serial_input" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
    fi
}

# ------------------------------------------------------------------------------
# Function: get_device_by_serial
# Input: Serial number string
# Output: Prints the device path (e.g., /dev/sdb) to stdout
# ------------------------------------------------------------------------------
get_device_by_serial() {
    local target_serial="$1"
    
    if [ -z "$target_serial" ]; then
        echo "Error: Serial number parameter is empty." >&2
        return 1
    fi

    local dev_name=""

    # Method 1: Check via lsblk
    
    #dev_name=$(lsblk -dno NAME,SERIAL | awk -v serial="$target_serial" '$2 == serial {print $1}')
    # Find device matching the normalized target serial/signature across both SERIAL and WWN columns
    dev_name=$(lsblk -dno NAME,SERIAL,WWN | awk -v target="$target_serial" '
        {
            # Combine columns 2 and 3 and convert to lowercase for universal matching
            combined = tolower($2 " " $3)
            t = tolower(target)
            
            # If the target signature exists anywhere inside the serial/WWN string, match it!
            if (length(t) > 0 && index(combined, t) > 0) {
                print $1
                exit
            }
        }
    ')

    if [ -n "$dev_name" ]; then
        echo "/dev/$dev_name"
        return 0
    fi

    # Method 2: Fallback check using udevadm
    for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        [ -e "$disk" ] || continue
        
        local id_serial id_serial_short
        id_serial=$(udevadm info --query=property --name="$disk" 2>/dev/null | grep '^ID_SERIAL=' | cut -d'=' -f2)
        id_serial_short=$(udevadm info --query=property --name="$disk" 2>/dev/null | grep '^ID_SERIAL_SHORT=' | cut -d'=' -f2)

        if [ "$id_serial" = "$target_serial" ] || [ "$id_serial_short" = "$target_serial" ]; then
            echo "$disk"
            return 0
        fi
    done

    echo "Error: No device found matching serial number '$target_serial'." >&2
    return 1
}

# ------------------------------------------------------------------------------
# Function: validate_disk
# Input: Device path
# Description: Ensures the device is valid and not currently mounted.
# ------------------------------------------------------------------------------
validate_disk() {
    local dev_path="$1"

    if [ ! -b "$dev_path" ]; then
        echo "Error: Device '$dev_path' is not a valid block device." >&2
        return 1
    fi

    # Check if any partitions on this device are currently mounted
    if lsblk -no MOUNTPOINTS "$dev_path" | grep -q '[a-zA-Z0-9]'; then
        echo "Error: Device '$dev_path' or its partitions have active mounts. Unmount them first." >&2
        return 1
    fi
}

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
    format_disk_gpt_ext4 "$target_device"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi