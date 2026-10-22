#!/usr/bin/env bash
# Build images listed in matrix.json; optionally smoke-test and push them.
# Used by CI and as the local fallback.
#
# Usage: scripts/build.sh [--smoke] [--push] [--date YYYYMMDD] [id ...]
#   no ids     all images in matrix.json
#   --smoke    run tests/smoke.sh on each image after building
#   --push     push all tags of each image (after the smoke test, if --smoke is given)
#   --date     date used in immutable tags (default: today, UTC)
#
# Requires: docker buildx, jq. Log in to Docker Hub before --push.
set -eo pipefail

cd "$(dirname "$0")/.."
REPO=maidea/webserver
PLATFORM=linux/amd64
SMOKE=0 PUSH=0 DATE=$(date -u +%Y%m%d) IDS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --smoke) SMOKE=1 ;;
        --push) PUSH=1 ;;
        --date) DATE=$2; shift ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) IDS+=("$1") ;;
    esac
    shift
done
if [ ${#IDS[@]} -eq 0 ]; then
    while IFS= read -r i; do IDS+=("$i"); done < <(jq -r '.images[].id' matrix.json)
fi

for id in "${IDS[@]}"; do
    img=$(jq -c --arg id "$id" '.images[] | select(.id == $id)' matrix.json)
    [ -n "$img" ] || { echo "unknown image id: $id" >&2; exit 2; }
    field() { jq -r "$1" <<< "$img"; }

    # --pull: never build from a stale local copy of a public base image
    # (images with a prebuild use the local maidea-local/* base instead; their prebuild pulls)
    args=(--platform "$PLATFORM" --load)
    [ "$(field .prebuild)" = null ] && args+=(--pull)
    [ "$(field .target)" != null ] && args+=(--target "$(field .target)")
    while IFS= read -r kv; do args+=(--build-arg "$kv"); done < <(field '.args | to_entries[] | "\(.key)=\(.value)"')
    if [ "$(field .base)" != null ]; then
        # Recorded so the upstream check can tell when the base image has changed
        base_digest=$(docker buildx imagetools inspect "$(field .base)" --format '{{json .Manifest.Digest}}' | tr -d '"')
        args+=(--label "org.opencontainers.image.base.name=docker.io/library/$(field .base)")
        args+=(--label "org.opencontainers.image.base.digest=$base_digest")
    fi
    tags=()
    while IFS= read -r t; do tags+=("$REPO:$t"); done < <(field '.tags[]')
    for t in "${tags[@]}"; do args+=(-t "$t"); done

    echo "::group::build $id"
    if [ "$(field .prebuild)" != null ]; then
        # Local base image the Dockerfile builds FROM (e.g. the patched PHP 7.4); never pulled or pushed
        docker buildx build --platform "$PLATFORM" --pull --load -t "$(field .prebuild.tag)" "$(field .prebuild.context)"
    fi
    docker buildx build "${args[@]}" "$(field .context)"
    echo "::endgroup::"

    php_version=$(docker run --rm --platform "$PLATFORM" "${tags[0]}" php -r 'echo PHP_VERSION;')
    if [ "$(field .base)" != null ]; then
        upstream=$(docker buildx imagetools inspect "$(field .base)" --format '{{json .Image}}' \
            | jq -r '."linux/amd64".config.Env[] | select(startswith("PHP_VERSION=")) | sub("PHP_VERSION="; "")')
        [ "$php_version" = "$upstream" ] || { echo "$id: built PHP $php_version, but $(field .base) is PHP $upstream" >&2; exit 1; }
    fi
    if [ "$(field .immutable_prefix)" != null ]; then
        # Immutable tags are never overwritten: if the name already exists (e.g. a second build that day), add .2, .3, ...
        immutable="$REPO:$(field .immutable_prefix)$php_version-$DATE" n=1
        while docker buildx imagetools inspect "$immutable" > /dev/null 2>&1; do
            n=$((n + 1)); immutable="$REPO:$(field .immutable_prefix)$php_version-$DATE.$n"
        done
        docker tag "${tags[0]}" "$immutable"
        tags+=("$immutable")
    fi

    if [ $SMOKE = 1 ]; then
        tests/smoke.sh "${tags[0]}" "$(field .smoke)" "$(field .php)"
    fi

    if [ $PUSH = 1 ]; then
        for t in "${tags[@]}"; do docker push --quiet "$t"; done
    fi
    echo "$id: ${tags[*]}"
done
