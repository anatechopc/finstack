#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for group in core loans; do
  echo "=== Updating dependencies in $group ==="
  cd "$SCRIPT_DIR/$group"
  for folder in */; do
    if [[ ! -d "$folder" ]]; then
      echo "$folder is file"
      continue
    fi
    echo "Updating dependencies in $group/$folder"
    cd "$folder"
    fvm flutter pub upgrade --major-versions
    cd ..
  done
done
