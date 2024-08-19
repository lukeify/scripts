#!/bin/zsh
# The script functions as a udev rule to ensure that if a FIDO2 token is ejected/removed from a system, and open
# block devices that are open and can be unlocked with that FIDO2 token are automatically closed. Setup details:
#
# Create a `udev` rule file that contains the
#
# Finally, call `close_all` on the `encrypted_files` script to perform the actual closing mechanics.
#
encrypted_files close_all
