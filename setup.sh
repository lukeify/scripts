#!/usr/bin/env zsh

if [[ ! -d /usr/local/bin ]]; then
  echo "Creating /usr/local/bin directory"
  mkdir -p /usr/local/bin
fi

if [[ ! -d "$HOME/.scripts" ]]; then
  echo "Creating ~/.scripts/ directory"
  mkdir -p "$HOME/.scripts"
fi

for file in src/*.sh; do
  filename=$(basename "$file" .sh)
  cp "$file" "/usr/local/bin/$filename"
done
