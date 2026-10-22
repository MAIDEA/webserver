#!/usr/bin/env bash
# Print the ids (JSON array) of images in matrix.json affected by changes since <base-ref>.
# Usage: scripts/changed-images.sh <base-ref> [--publish]
#   --publish   for publishing: tooling changes do not republish frozen legacy images
#               (they are republished only when their own files change)
set -eo pipefail

cd "$(dirname "$0")/.."
changed=$(git diff --name-only "$1" HEAD)

# Build tooling affects every image (only the tracked ones when publishing).
# changed-images.sh and outdated-images.sh only decide what to build, so they are not included.
if grep -qE '^(matrix\.json|scripts/build\.sh|tests/|\.github/workflows/build\.yml)' <<< "$changed"; then
    if [ "$2" = --publish ]; then jq -c '[.images[] | select(.track_upstream) | .id]' matrix.json
    else jq -c '[.images[].id]' matrix.json; fi
    exit
fi

# Otherwise: images whose build context (or prebuild context) changed
jq -c --arg changed "$changed" '
    ($changed | split("\n")) as $files
    | def touched($dir): $dir != null and any($files[]; if $dir == "." then test("^(Dockerfile|config/|\\.dockerignore)") else startswith($dir + "/") end);
    [.images[] | select(touched(.context) or touched(.prebuild.context)) | .id]
' matrix.json
