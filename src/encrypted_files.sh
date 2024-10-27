#!/usr/bin/env zsh

##
# Provides functionality to expedite the creating, opening, and closing of LUKS2 encrypted files using `losetup`,
# `cryptsetup`, and `mount`.
# Usage to create an encrypted file:
#
# $ krypton create <size> <mount_point>
#
# Usage to open an encrypted file:
#
# $ krypton open <path_to_file> <path_to_other_file>
#
# The file will be associated with a loop device, opened with cryptsetup, and mounted to a location on disk.
# Usage to close a mounted block device:
#
# $ krypton close <path_to_file> <path_to_other_file>
#
# Pass the `-a` flag with no file arguments to close all devices.

# Don't print out pre-assigned local variables
setopt TYPESET_SILENT
# Early exit when a script returns a non-zero exit code
set -e

# ----------------------------------------------------
# HELPERS
# ----------------------------------------------------

##
# Uses `losetup` to automate the opening of a loop device, returning the loop device's path on disk when complete. If
# this command fails, halt further execution of the script.
#
# Args:
# $1: The encrypted file name that a loop device should be created for.
#
setup_loop_device() {
  local encrypted_file_name="$1"
  local loop_device

  if ! loop_device=$(losetup -f --show "$encrypted_file_name"); then
    echo "Failed to set up loop device for $encrypted_file_name" >&2
    exit 1
  fi

  echo "$loop_device"
}

##
# Uses `losetup` to automate the closing of a loop device.
#
# Args:
# $1: The encrypted file name that a loop device exists for that should be closed.
#
close_loop_device() {
  local encrypted_file_name="$1"

  local loop_device=get

  losetup -d "$loop_device"
}

##
# Given a loop_device address, such as `/dev/loop1`, returns the suffixing number of that path, so for that address
# example, the returned value will be "1".
#
# Args:
# $1: The loop device address to return the number for.
#
get_loop_device_number() {
  local loop_device="$1"
  # sed is perfectly fine here
  # shellcheck disable=SC2001
  echo "$loop_device" | sed 's/[^0-9]*\([0-9]*\)$/\1/'
}

##
# Makes a directory and them mounts the mapper to that directory.
#
# Args:
# $1: The path on disk where the device should be mounted to.
# $2: The numerical identifier of the device to be mounted.
#
mount_device() {
  local mount_point="$1"
  local device_number="$2"

  mkdir "$mount_point/$device_number"
  mount "/dev/mapper/$device_number.unencrypted" "$mount_point/$device_number"
}

##
# Unmounts a mapper from a directory, then removes that directory.
#
# Args:
# $1: The path on disk where the device is mounted.
# $2: The numerical identifier of the device to unmount.
#
unmount_device() {
  local mount_point="$1"
  local device_number="$2"

  unmount "$mount_point/$device_number"
  # This parameter expansion solves SC2115.
  rm -r "$mount_point/${device_number:?}"
}

##
# Utility function to unmount, close, and deloop a block device.
#
# Args:
# $1: The name of the block mapper, ie. 1.encry
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

    sudo -u user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send "LUKS device ejected" "$1 $2"
}

##
# Request confirmation from the user via the `y` character.
# zsh-specific way of confirming input from the user. https://unix.stackexchange.com/a/198374
#
# Args
# $1: The message to be displayed to the user prior to being prompted.
#
confirm_with_message_prompt() {
  local message_prompt="$1"
  printf >&2 "%s " "$message_prompt: "
  read -r confirm
  if [[ ! "$confirm" =~ ^[y]$ ]]; then
      echo "Other input detected. Cancelling."
      exit 1
  fi
}

# ----------------------------------------------------
# MAIN FUNCTIONS
# ----------------------------------------------------

##
# Creates a LUKS-encrypted block device. The name of the encrypted file that backs the block device will be the next
# sequential number in the directory, i.e. if a `3.encrypted` file exists, then the next file name will be
# `4.encrypted`.
#
# During the process, the user will be prompted to insert their two FIDO2 security keys which will be used to encrypt
# and secure the LUKS volume.
#
# Args:
# $1: The number of megabytes the encrypted file should be. Specify 1024 for 1GB, 2048 for 2GB, etc.
# $2: The mount point for the created block file on disk.
#
create_block_device() {
  local megabytes=$1
  local mount_point=$2

  local i=1
  while [[ -e "$mount_point/$i.encrypted" ]]; do ((i++)); done;
  local encrypted_file_name="$i.encrypted"

  dd if=/dev/zero of="$mount_point/$encrypted_file_name" bs=1M count="$megabytes" status=none

  local loop_device
  loop_device=$(setup_loop_device "$mount_point/$encrypted_file_name")
  local device_number
  device_number=$(get_loop_device_number "$loop_device")

  # Initialize the LUKS partition with a passphrase provided by writing /dev/zero to a file. We replace this password
  # with FIDO2 keyslots. This approach minimizes user input. We set the key slot to 2 so that the tokens (and the
  # corresponding key slots they consume) have aligned numbers, i.e. token 0 will correspond to key slot 0.
  dd if=/dev/zero of=zero.key bs=1 count=8 status=none
  # cryptsetup warns of this key being too permissive if left as 644.
  chmod 400 zero.key
  # Use -q flag to enable batch mode to disable confirmation of data overwriting.
  cryptsetup -q luksFormat "$loop_device" --key-file=zero.key --key-slot=2

  local i_fido_loop=0
  until [ "$i_fido_loop" -gt 1 ]; do
    if [ "$i_fido_loop" -eq 0 ]; then
      confirm_with_message_prompt "Insert the first FIDO2 key, and confirm (y) when complete"
    else
      confirm_with_message_prompt "Insert the second FIDO2 key, and confirm (y) when complete"
    fi

    # Loop over each FIDO2 token in /dev/hidraw, stopping when a FIDO2 token is found.
    for device in /dev/hidraw*; do
      local hidraw_info
      hidraw_info=$(udevadm info "$device")

      if printf "%s" "$hidraw_info" | grep -q "ID_FIDO_TOKEN=1"; then
        echo "Found FIDO2 token $device, enrolling as key $i_fido_loop"

        systemd-cryptenroll "$loop_device" \
          --unlock-key-file=zero.key \
          --fido2-device="$device" \
          --fido2-with-user-presence=yes

        break
      fi
    done

    # https://stackoverflow.com/q/49072730
    ((++i_fido_loop))
  done

  # Wipe keyslot 0 associated with our empty passphrase.
  echo "Enrollment complete. Removing empty passphrase & associated keyfile."
  cryptsetup luksRemoveKey "$loop_device" --key-file=zero.key
  rm zero.key

  # Open partition, and initialise an EXT4 filesystem.
  cryptsetup open --token-only "$loop_device" "$device_number.unencrypted"
  mkfs.ext4 "/dev/mapper/$device_number.unencrypted"

  confirm_with_message_prompt "Confirm (y) when the mount point is available"

  mount_device "$mount_point" "$device_number"
  # change ownership of the mounted partition to ensure the user can write to it.
  chown user:user "$mount_point/$device_number"
}

##
# Opens a block device. This is a three command process:
#
# 1. Use `losetup` to setup a loop device from a given backing file.
# 2. `cryptsetup-open` to open the loop device, unlocking using FIDO2.
#    https://man7.org/linux/man-pages/man8/cryptsetup-open.8.html
# 3. Mount loop device using `mount`.
#
# Args:
# $1: The name of the file to be opened, i.e. `1.encrypted`.
#
open_block_device () {
  local encrypted_file_name="$1"

  local loop_device
  loop_device=$(setup_loop_device "$encrypted_file_name")
  local device_number
  device_number=$(get_loop_device_number "$loop_device")

  if ! cryptsetup open --token-only "$loop_device" "$device_number.unencrypted"; then
    echo "cryptsetup failed to open $loop_device" >&2
    exit 1
  fi

  mount_device "$PWD" "$device_number"
}

##
# Closes a block device given by the filename.
#
# Args:
# $1: The name of the file to be closed, i.e. `1.encrypted`.
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
      # The corresponding loop device, for example: /dev/loop1
      local found_loop_device
      found_loop_device=$(echo "$output" | grep 'device:' | awk '{print $2}')

      local device_number
      device_number=$(echo "$encrypted_file_name" | awk -F'.' '{print $1}')

      # The path to the loop—of which we care about the mount point.
      local mount_point
      mount_point=$(echo "$output" | grep "loop:" | awk '{print $2}' | xargs dirname)

      # The
      break
    fi
  done

  if [ -n "$mount_point" ] && [ -n "$device_number" ]; then
    echo "No mapper was found for $1" >&2
    exit 1
  fi

  unmount_device "$mount_point" "$device_number"

  cryptsetup close "$encrypted_file_name"
  losetup -d "$found_loop_device"

  sudo -u user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send "LUKS device ejected" "$1 $2"
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

# ----------------------------------------------------
# ENTRYPOINT
# ----------------------------------------------------

# Parse the first argument as either the string "open" or "close", and assign the function to be called to the
# variable `$call`. If the argument provided is "close_all", call the corresponding method and finish.
case "$1" in
  create)
    create_block_device "$2" "$3"
    exit 0
    ;;
  open)
    call=open_block_device
    ;;
  close)
    call=close_block_device
    ;;
  close_all)
    # TODO: This was changed to have an -a flag on close instead.
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
