#!/usr/bin/env bash
# Provides functionality to expedite the opening and closing of LUKS2 encrypted files using `losetup`,
# `cryptsetup`, and `mount`. Usage to open an encrypted file:
#
# $ encrypted_file open /path/to/file
#
# The file will be associated with a loop device, opened with cryptsetup, and mounted to a location on disk.
# Usage to close a mounted block device:
#
# $ encrypted_file close /path/to/mount
#
#

# Early exit if a command fails.
set -e

##
# Opens a block device. This is a three command process:
#
# 1. Use `losetup` to
# 2. `cryptsetup-open` to open the loop device, unlocking using FIDO2.
#    https://man7.org/linux/man-pages/man8/cryptsetup-open.8.html
# 3. Mount loop device using `mount`.
#
# Args:
# 1. The name of the file to be opened, i.e. `test.encrypted`.
#
open_block_device () {
  loop_device=$(losetup -f --show "$1")
  # TODO: Check if the command succeeded first.
  #  if ! losetup -f $1 2>&2; then
  #    exit 1
  #  fi

  # shellcheck disable=SC2001
  # sed is perfectly fine here
  device_number=$(echo "$loop_device" | sed 's/[^0-9]*\([0-9]*\)$/\1/')
  cryptsetup open "$loop_device" "${device_number}.encryptedvolume"
# TODO: Handle failure
  # Create the directory that the block device will be mounted to.
  mkdir /mnt/"${device_number}"
  mount /dev/mapper/"${device_number}".encryptedvolume /mnt/"${device_number}"
}

##
# Closes a block device given by the filename.
#
# Args:
# 1. The name of the file to be closed, i.e. `test.encrypted`.
#
close_block_device() {
  # Given the file name of the encrypted LUKS block device, find the corresponding mapper by interrogating
  # `cryptsetup status` which will list out the backing file.
  for mapper in /dev/mapper/*; do
    output=$(cryptsetup status "$(basename "$mapper")")

    if echo "$output" | grep -q "$1"; then
      # We found a matching device. Perform variable assignments.
      # Given the path /dev/mapper/1.encryptedvolume, extracts the basename.
      found_block_mapper_name=$(basename "$mapper")
      # The corresponding loop device, for example: /dev/loop1
      found_loop_device=$(echo "$output" | grep 'device:' | awk '{print $2}')
      break
    fi
  done

  if [ -z "$found_block_mapper_name" ]; then
    echo "No mapper was found for $1" >&2
    exit 1
  fi

  # call: unmount_close_and_deloop 1.encryptedvolume /dev/loop1
  unmount_close_and_deloop "$found_block_mapper_name" "$found_loop_device"
}

##
# Utility function to unmount, close, and deloop a block device.
#
# Args:
# $1: The name of the block mapper, ie. 1.encryptedvolume
# $2: The loop device location, ie. /dev/loop1
#
unmount_close_and_deloop() {
    # Given a block name such as `1.encryptedvolume`, extracts only the number from that name.
    found_block_mapper_number=$(echo "$1" | awk -F'.' '{print $1}')

    # Unmount the block, and delete the mount point
    umount "/mnt/$found_block_mapper_number"
    rm -r "/mnt/${found_block_mapper_number:?}"

    cryptsetup close "$1"
    losetup -d "$2"

    # Yes, this is hardcoded to assume my username and uid. That's okay, because this script isn't meant for you.
    sudo -u luke DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send "LUKS device ejected" "$1 $2"
}

##
# Closes all open block devices managed by `encrypted_files`. This is assumed to be any available device mappings
# that are unlocked via FIDO2.
#
# Begins by using `dmsetup` to list all device mappings managed by cryptsetup. This may list out other devices as well,
# such as the NVME disk itself; and potentially the swapfile too. These don't need to be ejected, so we further filter
# on whether the devices have keyslots that are unlocked via FIDO2 devices only.
#
close_all_block_devices() {
  for dev in $(dmsetup ls --target crypt | awk '{print $1}'); do
    cryptsetup_status=$(cryptsetup status "$dev")
    loop_device=$(echo "$cryptsetup_status" | grep device | awk '{print $2}')

    if cryptsetup isLuks "$loop_device" && cryptsetup luksDump "$loop_device" | grep -q "fido2" && cryptsetup status "$dev" | grep -q "is active"; then
      echo "$dev is a LUKS device, is open, and is unlocked via FIDO2. Unmounting, closing, and delooping..."
      unmount_close_and_deloop "$dev" "$loop_device"
    fi
  done
}

# Parse the first argument as either the string "open" or "close", and assign the function to be called to the
# variable `$call`. If the argument provided is "close_all", call the corresponding method and finish.
case "$1" in
  open)
    call=open_block_device
    ;;
  close)
    call=close_block_device
    ;;
  close_all)
    echo "Closing all block devices"
    close_all_block_devices
    exit 0
    ;;
  *)
    echo "Please provide either 'open' or 'close to 'encrypted_block_devices." >&2
    exit 1
    ;;
esac

# Accept the remaining arguments as paths to mountable block devices, and determine the count provided.
block_device_paths=("${@:2}")
# block_device_path_count=${#block_device_paths[@]}
# TODO: If path count is 0, open or close all files in the current directory.

for block_device_path in "${block_device_paths[@]}"; do
  # echo "Block device: ${block_device_path}"
  # When given a file, run the user-specified function on the block device path.
  if [ -f "$block_device_path" ]; then
    # Perform file operation
    $call "$block_device_path"
# TODO: Handle directories
#  elif [ -d "$block-device_path" ]; then
#    # Perform dir operation
  else
    echo "$block_device_path: Argument provided was not a file." >&2
    exit 1
  fi
done
