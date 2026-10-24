#!/usr/bin/env bash
# Print the current version of a package in Ondřej Surý's PHP repository for Debian 12 (amd64),
# which the legacy images install PHP from ("php_package" in matrix.json).
# Usage: scripts/php-package-version.sh <package>
set -eo pipefail

index=$(curl -fsSL https://packages.sury.org/php/dists/bookworm/main/binary-amd64/Packages.gz | gunzip)
version=$(awk -v p="$1" '$1 == "Package:" { found = ($2 == p) } found && $1 == "Version:" { print $2; exit }' <<< "$index")
[ -n "$version" ] || { echo "package not found: $1" >&2; exit 1; }
echo "$version"
