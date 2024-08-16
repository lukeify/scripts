#!/bin/zsh
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

# Parse the first argument as either the string "open" or "close".
case "$1" in
  open)
    call=open_block_device
    ;;
  close)
    call=close_block_device
    ;;
  *)
    echo "Please provide either 'open' or 'close to 'encrypted_block_devices." &>2
    exit 1
    ;;
esac

# Accept the remaining arguments as paths to mountable block devices, and determine the count provided.
block_device_paths=("${@:2}")
# block_device_path_count=${#block_device_paths[@]}
# TODO: If path count is 0, open or close all files in the current directory.

for block_device_path in "${block_device_paths[@]}"; do
  echo "Block device: ${block_device_path}"
  # When given a file, run the user-specified function on the block device path.
  if [ -f "$block_device_path" ]; then
    # Perform file operation
    $call "$block_device_path"
# TODO: Handle directories
#  elif [ -d "$block-device_path" ]; then
#    # Perform dir operation
  else
    echo "Argument provided was not a file." &>2
    exit 1
  fi
done

# If given a file
  # Run the "open_block_device" function on it.
# If given an array of files
  # Run the "open_block_device" function on all files
# If given a directory
  # Run the "open_block_device" function on each top-level file in the directory

# Opens a block device. This is a three command process:
#
# 1. Use `losetup` to
# 2. `cryptsetup-open` to
# https://man7.org/linux/man-pages/man8/cryptsetup-open.8.html
#
open_block_device () {
  loop_device=$(losetup -f --show $1)
# TODO: Check if the command succeeded first.
#  if ! losetup -f $1 2>&2; then
#    exit 1
#  fi

# TODO: Generate a better name for the mapping
  # shellcheck disable=SC2001
  # sed is perfectly fine here
  device_number=$(echo "$loop_device" | sed 's/[^0-9]*\([0-9]*\)$/\1/')
  cryptsetup open "$loop_device" "${device_number}.encryptedvolume" --fido2-device=auto
# TODO: Handle failure

  mount /dev/mapper/"${device_number}".encryptedvolume /mnt/"${device_number}"
}

close_block_device() {
  umount "$1"
  # TODO: What to close?
  cryptsetup close
  losetup -d /dev/loop"$1"
}
