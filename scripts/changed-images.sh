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
tooling=false
if grep -qE '^(matrix\.json|scripts/build\.sh|tests/|\.github/workflows/build\.yml)' <<< "$changed"; then
    if [ "$2" != --publish ]; then jq -c '[.images[].id]' matrix.json; exit; fi
    tooling=true
fi

# Plus images whose build context (or prebuild context) changed, e.g. a new legacy image
jq -c --arg changed "$changed" --argjson tooling "$tooling" '
    ($changed | split("\n")) as $files
    | def touched($dir): $dir != null and any($files[]; if $dir == "." then test("^(Dockerfile|config/|\\.dockerignore)") else startswith($dir + "/") end);
    [.images[] | select(($tooling and .track_upstream) or touched(.context) or touched(.prebuild.context)) | .id]
' matrix.json
