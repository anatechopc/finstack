#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for group in core loans; do
  echo "=== Cleaning packages in $group ==="
  cd "$SCRIPT_DIR/$group"
  for folder in */; do
    if [[ ! -d "$folder" ]]; then
      echo "$folder is file"
      continue
    fi
    echo "Cleaning $group/$folder"
    cd "$folder"
    fvm flutter clean
    cd ..
  done
done
