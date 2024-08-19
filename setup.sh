#!/usr/bin/env bash
for file in src/*.sh; do
  cp "$file" "${file%.sh}"
done
