#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for group in core loans; do
  echo "=== Building models in $group ==="
  cd "$SCRIPT_DIR/$group"
  for folder in */; do
    if [[ ! -d "$folder" ]]; then
      echo "$folder is file"
      continue
    fi
    echo "Building models in $group/$folder"
    cd "$folder"
    fvm flutter pub run build_runner build --delete-conflicting-outputs
    cd ..
  done
done
