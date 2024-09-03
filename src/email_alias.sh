#!/usr/bin/env zsh

##
# Uses /dev/urandom to generate a cryptographically random string that is appended to a provided email prefix. Once
# generated, the output is copied to the clipboard.
#
# https://security.stackexchange.com/a/183951
#
# Arguments:
# $1 The prefix that should be applied to the randomly-generated string of characters. This is provided by the user.
#
secure_chars=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 16; echo)
out="$1.$secure_chars"
echo "$out" | pbcopy
echo "Copied \"$out\" to clipboard."
