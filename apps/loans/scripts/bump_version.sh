#!/bin/bash
set -e

PUBSPEC="pubspec.yaml"
MODE=${1:-dev}

# Extract current version
pubspec_version=$(grep '^version:' "$PUBSPEC" | sed 's/version: //')
echo "Current version: $pubspec_version"

IFS='+' read -r current_version build_number <<< "$pubspec_version"
IFS='-' read -r base prerelease <<< "$current_version"
IFS='.' read -r major minor patch <<< "$base"

bump_dev() {
  if [[ "$prerelease" != dev* ]]; then
    patch=$((patch + 1))
    new_version="${major}.${minor}.${patch}-dev.1"
  else
    dev_num=$(echo "$prerelease" | sed 's/dev\.//')
    dev_num=$((dev_num + 1))
    new_version="${major}.${minor}.${patch}-dev.${dev_num}"
  fi
}

bump_staging() {
  if [[ "$prerelease" == dev* ]]; then
    # Remove -dev.N, set -pre.1
    new_version="${major}.${minor}.${patch}-pre.1"
  elif [[ "$prerelease" == pre* ]]; then
    pre_num=$(echo "$prerelease" | sed 's/pre\.//')
    pre_num=$((pre_num + 1))
    new_version="${major}.${minor}.${patch}-pre.${pre_num}"
  else
    new_version="${major}.${minor}.${patch}-pre.1"
  fi
}

bump_production() {
  if [[ "$prerelease" == pre* ]]; then
    # Remove -pre.N for release merges
    new_version="${major}.${minor}.${patch}"
  elif [[ "$prerelease" == fix* ]]; then
    fix_num=$(echo "$prerelease" | sed 's/fix\.//')
    fix_num=$((fix_num + 1))
    new_version="${major}.${minor}.${patch}-fix.${fix_num}"
  else
    new_version="${major}.${minor}.${patch}-fix.1"
  fi
}

case "$MODE" in
  dev)
    bump_dev
    ;;
  staging)
    bump_staging
    ;;
  production)
    bump_production
    ;;
  *)
    echo "Unknown mode: $MODE. Use dev, staging, or production."
    exit 1
    ;;
esac

# Get current timestamp in milliseconds
build_number=$(($(date +%s%N)/1000000))

# Append build number to version
sed -i "s/^version: .*/version: $new_version+$build_number/" "$PUBSPEC"
echo "Bumped version to: $new_version+$build_number"