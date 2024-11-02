#!/usr/bin/env bash
for file in src/*.{sh,rb}; do
  [ -e "$file" ] || continue
  cp "$file" "${file%.*}"
done
