#!/usr/bin/env bash
# Print the ids (JSON array) of published images whose sources have changed since they were built:
# - the base image: the org.opencontainers.image.base.digest label (set by build.sh) differs from its current digest
# - for images with "php_package": the hr.maidea.php-package label differs from the package's current version
# Only images with "track_upstream": true are checked.
set -eo pipefail

cd "$(dirname "$0")/.."
REPO=maidea/webserver
outdated=()

while IFS=$'\t' read -r id tag base package; do
    labels=$(docker buildx imagetools inspect "$REPO:$tag" --format '{{json .Image}}' 2>/dev/null \
        | jq -c '(if has("config") then . else ."linux/amd64" end).config.Labels // {}' || echo '{}')
    built=$(jq -r '.["org.opencontainers.image.base.digest"] // empty' <<< "$labels")
    current=$(docker buildx imagetools inspect "$base" --format '{{json .Manifest.Digest}}' | tr -d '"')
    if [ "$built" != "$current" ]; then
        echo "$id: base $base changed (built from ${built:-unknown}, now $current)" >&2
        outdated+=("$id")
        continue
    fi
    if [ -n "$package" ]; then
        built=$(jq -r '.["hr.maidea.php-package"] // empty' <<< "$labels")
        current="$package=$(scripts/php-package-version.sh "$package")"
        if [ "$built" != "$current" ]; then
            echo "$id: PHP package changed (built from ${built:-unknown}, now $current)" >&2
            outdated+=("$id")
            continue
        fi
    fi
    echo "$id: up to date" >&2
done < <(jq -r '.images[] | select(.track_upstream) | [.id, .tags[0], .base, (.php_package // "")] | @tsv' matrix.json)

if [ ${#outdated[@]} -eq 0 ]; then echo '[]'; else printf '%s\n' "${outdated[@]}" | jq -R . | jq -sc .; fi
