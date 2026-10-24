#!/usr/bin/env bash
# Print the ids (JSON array) of images in matrix.json affected by changes since <base-ref>.
# Usage: scripts/changed-images.sh <base-ref> [--publish]
#   --publish   for publishing: tooling changes republish only the images that track upstream,
#               and changes to tests/ alone publish nothing (build.yml smoke-tests the published images instead)
set -eo pipefail

cd "$(dirname "$0")/.."
changed=$(git diff --name-only "$1" HEAD)

# Pull requests: build tooling, files shared by all images (shared/) and smoke tests affect every image.
# changed-images.sh and outdated-images.sh only decide what to build, so they are not included.
if [ "$2" != --publish ] && grep -qE '^(shared/|scripts/(build|php-package-version)\.sh|tests/|\.github/workflows/build\.yml)' <<< "$changed"; then
    jq -c '[.images[].id]' matrix.json
    exit
fi

# Publishing: build tooling and shared/ changes republish the tracked images
tooling=false
if grep -qE '^(shared/|scripts/(build|php-package-version)\.sh|\.github/workflows/build\.yml)' <<< "$changed"; then tooling=true; fi

# Plus images whose matrix.json entry is new or changed, and images whose build context changed
old=$(git show "$1:matrix.json" 2>/dev/null || echo '{"images": []}')
jq -c --arg changed "$changed" --argjson tooling "$tooling" --argjson old "$old" '
    ($changed | split("\n")) as $files
    | def touched($dir): $dir != null and any($files[]; if $dir == "." then test("^(Dockerfile|config/|\\.dockerignore)") else startswith($dir + "/") end);
    [.images[] | . as $img
     | select(($tooling and .track_upstream)
              or ([$old.images[] | select(.id == $img.id)][0] != $img)
              or touched(.context))
     | .id]
' matrix.json
