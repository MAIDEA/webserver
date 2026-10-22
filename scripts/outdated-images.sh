#!/usr/bin/env bash
# Print the ids (JSON array) of published images whose base image has changed since they were built.
# Compares the org.opencontainers.image.base.digest label of the published image (set by build.sh)
# with the current digest of its base image. Only images with "track_upstream": true are checked.
set -eo pipefail

cd "$(dirname "$0")/.."
REPO=maidea/webserver
outdated=()

while IFS=$'\t' read -r id tag base; do
    current=$(docker buildx imagetools inspect "$base" --format '{{json .Manifest.Digest}}' | tr -d '"')
    built=$(docker buildx imagetools inspect "$REPO:$tag" --format '{{json .Image}}' 2>/dev/null \
        | jq -r '."linux/amd64".config.Labels["org.opencontainers.image.base.digest"] // empty' || true)
    if [ "$built" != "$current" ]; then
        echo "$id: base $base changed (built from ${built:-unknown}, now $current)" >&2
        outdated+=("$id")
    else
        echo "$id: up to date" >&2
    fi
done < <(jq -r '.images[] | select(.track_upstream) | [.id, .tags[0], .base] | @tsv' matrix.json)

if [ ${#outdated[@]} -eq 0 ]; then echo '[]'; else printf '%s\n' "${outdated[@]}" | jq -R . | jq -sc .; fi
