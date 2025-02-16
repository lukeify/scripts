#!/usr/bin/env zsh

##
# Uses /dev/urandom to generate a cryptographically random string that is appended to a provided email prefix. Once
# generated, an alias is created using SimpleLogin. Once complete, the output is copied to the clipboard.
#
# Arguments:
# $1 The prefix that should be applied to the randomly-generated string of characters. This is provided by the user.
#
# Variables stored in ~/.scripts/email_alias:
# SIMPLE_LOGIN_SUFFIX Shall be the domain name the email alias should be created with. This shall be prefixed with the
# `@` symbol, i.e. `@luke.example`.
# SIMPLE_LOGIN_API_TOKEN Shall be the API token used to communicate with SimpleLogin.
#
# Expected utilities:
# curl: Used to make requests to SimpleLogin.
# jq: Used to parse JSON responses from SimpleLogin.
#

# Read from config file
config_file="$HOME/.scripts/email_alias"

if [[ ! -f "$config_file" ]]; then
  echo "Error: configuration file $config_file not found." >&2
  exit 1
fi

source "$config_file"

api_fqdn="https://app.simplelogin.io/api"
auth_header="Authentication: $SIMPLE_LOGIN_API_TOKEN"

if [[ -z "$1" || -z "$SIMPLE_LOGIN_SUFFIX" || -z "$SIMPLE_LOGIN_API_TOKEN" ]]; then
  echo "Error: Missing required prefix, SIMPLE_LOGIN_SUFFIX, or SIMPLE_LOGIN_API_TOKEN." >&2
  exit 1
fi

# Chosen based on the discussion from https://security.stackexchange.com/a/183951
# This appears to generate cryptographically random characters.
secure_chars=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 16; echo)

# Get the Mailbox ID that the alias should be added to.
mailbox_id=$(curl -s "${api_fqdn}/v2/mailboxes" -H "$auth_header" | jq '.mailboxes[0].id')

# Retrieve the signed suffix that the alias should be created for.
signed_suffix=$(curl -s "${api_fqdn}/v5/alias/options" -H "$auth_header" | jq -r ".suffixes[] | select(.suffix == \"$SIMPLE_LOGIN_SUFFIX\") | .signed_suffix")

read -r -d '' json <<JSON
{
  "alias_prefix": "$1.$secure_chars",
  "signed_suffix": "$signed_suffix",
  "mailbox_ids": ["$mailbox_id"],
  "note": "$1"
}
JSON

response=$(curl -w "\n%{http_code}" -s "${api_fqdn}/v3/alias/custom/new" \
  -H "$auth_header" \
  -H "Content-Type: application/json" \
  -d "$json")

sl_response_code=$(echo "$response" | awk 'END{print $0}')

# Ensure the status code is 201.
if [ "$sl_response_code" -eq 201 ]; then
  generated_address=$(echo "$response" | awk 'NR==1{body=$0} END{print body}' | jq -r ".alias")
  echo "$generated_address" | pbcopy
  echo "Generated email alias \"$generated_address\" and copied it to your clipboard."
else
  echo "Could not generate email alias! Response code was $sl_response_code."
fi
