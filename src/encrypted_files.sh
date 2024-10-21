#!/usr/bin/env bash

##
# Provides functionality to expedite the creating, opening, and closing of LUKS2 encrypted files using `losetup`,
# `cryptsetup`, and `mount`. Usage to create an encrypted file:
#
# $ encrypted_file create <size>
#
# Usage to open an encrypted file:
#
# $ encrypted_file open /path/to/file
#
# The file will be associated with a loop device, opened with cryptsetup, and mounted to a location on disk. Usage to
# close a mounted block device:
#
# $ encrypted_file close /path/to/mount

# Early exit if a command fails.
set -e

# HELPERS

##
# Uses `losetup` to automate the opening of a loop device, returning the loop device's path on disk when complete.
#
# Args:
# $1 The encrypted file name that a loop device should be created for.
#
setup_loop_device() {
  local encrypted_file_name="$1"

  local loop_device
  loop_device=$(losetup -f --show "$encrypted_file_name")
  # TODO: Check if the command succeeded first.
  #  if ! losetup -f $1 2>&2; then
  #    exit 1
  #  fi
  echo "$loop_device"
}

##
# Given a loop_device address, such as `/dev/loop1`, returns the suffixing number of that path, so for that address
# example, the returned value will be "1".
#
# Args:
# $1 The loop device address to return the number for.
#
get_loop_device_number() {
  local loop_device="$1"
  # sed is perfectly fine here
  # shellcheck disable=SC2001
  echo "$loop_device" | sed 's/[^0-9]*\([0-9]*\)$/\1/'
}

prompt_for_fido_action() {
  local key_ordinal="$1" # first or second
  local key_action="$2" # insert or remove

  read -rp "Please $key_action your $key_ordinal FIDO2 key, and confirm (y) when complete: " confirm
  if [[ ! "$confirm" =~ ^[y]$ ]]; then
      echo "Other input detected. Cancelling."
      exit 1
  fi

}

# MAIN FUNCTIONS

##
# Creates a LUKS-encrypted block device. The name of the encrypted file that backs the block device will be the next
# sequential number in the directory, i.e. if a `3.encrypted` file exists, then the next file name will be
# `4.encrypted`.
#
# During the process, the user will be prompted to insert their two FIDO2 security keys which will be used to encrypt
# and secure the LUKS volume.
#
# Args:
# $1 The number of megabytes the encrypted file should be. Specify 1024 for 1GB, 2048 for 2GB, etc.
#
#
create_block_device() {
  local megabytes=$1

  local i=1
  while [[ -e "$i.encrypted" ]]; do ((i++)); done;
  local encrypted_file_name="$i.encrypted"

  dd if=/dev/zero of="$encrypted_file_name" bs=1M count="$megabytes"

  local loop_device
  loop_device=$(setup_loop_device "$encrypted_file_name")
  local device_number
  device_number=$(get_loop_device_number "$loop_device")

  # Initialize a LUKS partition with a near-empty password using input piped from echo. We replace this password with
  # FIDO2 keyslots next.
  echo -n "0" | cryptsetup luksFormat "$loop_device" -

  # Enroll the first key.
  prompt_for_fido_action "first" "insert"
  systemd-cryptenroll "$loop_device" \
    --wipe-slot=all \
    --fido2-device=auto \
    --fido2-with-user-presence=yes \
    --fido2-with-user-verification=yes
  prompt_for_fido_action "first" "remove"

  # Enroll the second key.
  prompt_for_fido_action "second" "insert"
  systemd-cryptenroll "$loop_device" \
    --fido2-device=auto \
    --fido2-with-user-presence=yes \
    --fido2-with-user-verification=yes
  prompt_for_fido_action "second" "remove"

  # TODO: Print confirmation of isLuks & luksDump.
}

##
# Opens a block device. This is a three command process:
#
# 1. Use `losetup` to
# 2. `cryptsetup-open` to open the loop device, unlocking using FIDO2.
#    https://man7.org/linux/man-pages/man8/cryptsetup-open.8.html
# 3. Mount loop device using `mount`.
#
# Args:
# 1. The name of the file to be opened, i.e. `1.encrypted`.
#
open_block_device () {
  local encrypted_file_name="$1"

  local loop_device
  loop_device=$(setup_loop_device "$encrypted_file_name")
  local device_number
  device_number=$(get_loop_device_number "$loop_device")

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
# 1. The name of the file to be closed, i.e. `1.encrypted`.
#
close_block_device() {
  local encrypted_file_name="$1"

  # Given the file name of the encrypted LUKS block device, find the corresponding mapper by interrogating
  # `cryptsetup status` which will list out the backing file.
  for mapper in /dev/mapper/*; do
    local output
    output=$(cryptsetup status "$(basename "$mapper")")

    if echo "$output" | grep -q "$encrypted_file_name"; then
      # We found a matching device. Perform variable assignments.
      # Given the path /dev/mapper/1.encryptedvolume, extracts the basename.
      local found_block_mapper_name
      found_block_mapper_name=$(basename "$mapper")

      # The corresponding loop device, for example: /dev/loop1
      local found_loop_device
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
    local found_block_mapper_number
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
    local cryptsetup_status
    cryptsetup_status=$(cryptsetup status "$dev")
    local loop_device
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
  create)
    create_block_device "$2"
    exit 0
    ;;
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
    echo "Please provide either 'create', 'open', or 'close to 'encrypted_files." >&2
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
