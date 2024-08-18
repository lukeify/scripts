#!/bin/zsh
# The script functions as a udev rule to ensure that if a FIDO2 token is ejected/removed from a system, and open
# block devices that are open and can be unlocked with that FIDO2 token are automatically closed. Setup details
#
# Create a `udev` rule file that contains the
#
#

# List all device mappings managed by `cryptsetup`. This may list out other devices as well, such as the NVME disk
# itself; and potentially the swapfile too. These don't need to be ejected, so we further filter on whether the devices
# have keyslots that are unlocked via FIDO2 devices only.
for dev in $(dmsetup ls --target crypt | awk '{print $1}'); do
  blkdev=$(cryptsetup status "$dev" | grep device | awk '{print $2}')
  echo $blkdev

  if cryptsetup luksDump "$blkdev" | grep -q "fido2" && cryptsetup status "$dev" | grep -q "is active"; then
    echo "$dev is open and is unlocked via FIDO2"
  fi
done
