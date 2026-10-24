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
# BUILD_CACHE=gha (CI): reuse build layers from the GitHub Actions cache (needs a docker-container buildx builder).
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

# Docker Hub counts manifest GET requests against a pull limit (200 an hour, shared with CI), but not HEAD requests.
# So every image a Dockerfile uses (its *_IMAGE build arguments) is pinned to its current digest, found with a HEAD
# request (scripts/registry-digest.sh), instead of --pull: no stale local copies, and downloads only when it changed.
CACHE=$(mktemp -d)
trap 'rm -rf "$CACHE"' EXIT
# Kept across runs: the linux/amd64 manifest of a base image's index (an index digest never changes)
KEEP=${XDG_CACHE_HOME:-$HOME/.cache}/maidea-webserver
mkdir -p "$KEEP"
# lookup <cache key> <command...>: run the command once per run, then print its cached output
lookup() {
    local f="$CACHE/${1//[^A-Za-z0-9.-]/_}"; shift
    if [ ! -f "$f" ]; then
        "$@" > "$f.tmp"
        [ -s "$f.tmp" ] || { echo "no result from: $*" >&2; return 1; }
        mv "$f.tmp" "$f"
    fi
    cat "$f"
}
amd64_digest() {  # <image@index digest>: its linux/amd64 manifest digest (one counted request the first time)
    local f="$KEEP/${1//[^A-Za-z0-9.-]/_}"
    if [ ! -s "$f" ]; then
        docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' \
            | jq -r '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64") | .digest' > "$f.tmp"
        [ -s "$f.tmp" ] || { echo "no linux/amd64 image in $1" >&2; return 1; }
        mv "$f.tmp" "$f"
    fi
    cat "$f"
}
# Docker Hub's web API, which does not count as pulls
tag_exists() {
    [ "$(curl -s -o /dev/null -w '%{http_code}' "https://hub.docker.com/v2/namespaces/${REPO%/*}/repositories/${REPO#*/}/tags/$1")" = 200 ]
}

for id in "${IDS[@]}"; do
    img=$(jq -c --arg id "$id" '.images[] | select(.id == $id)' matrix.json)
    [ -n "$img" ] || { echo "unknown image id: $id" >&2; exit 2; }
    field() { jq -r "$1" <<< "$img"; }

    args=(--platform "$PLATFORM" --load)
    if [ "${BUILD_CACHE:-}" = gha ]; then
        args+=(--cache-from "type=gha,scope=$id" --cache-to "type=gha,scope=$id,mode=max")
    fi
    # Files used by all images; the legacy Dockerfiles COPY --from=shared
    args+=(--build-context shared=shared)
    [ "$(field .target)" != null ] && args+=(--target "$(field .target)")
    while IFS= read -r kv; do args+=(--build-arg "$kv"); done < <(field '.args | to_entries[] | "\(.key)=\(.value)"')
    # The current base image, by digest (never a stale local copy); recorded for the upstream check
    base_digest=$(lookup "digest-$(field .base)" scripts/registry-digest.sh "$(field .base)")
    base_amd64=$(amd64_digest "$(field .base)@$base_digest")
    args+=(--build-arg "BASE_IMAGE=$(field .base)@$base_amd64")
    # The other images the Dockerfile uses (ARG <NAME>_IMAGE=<image:tag>), e.g. composer
    pins=$(sed -nE 's/^ARG ([A-Z_]+_IMAGE)=([^$ ]+)$/\1 \2/p' "$(field .context)/Dockerfile" | grep -v '^BASE_IMAGE ' || true)
    while read -r name image; do
        [ -n "$name" ] || continue
        digest=$(lookup "digest-$image" scripts/registry-digest.sh "$image")
        args+=(--build-arg "$name=$image@$digest")
    done <<< "$pins"
    args+=(--label "org.opencontainers.image.base.name=docker.io/library/$(field .base)")
    args+=(--label "org.opencontainers.image.base.digest=$base_digest")
    if [ "$(field .php_package)" != null ]; then
        # PHP from a package (legacy images): build its current version and record it for the upstream check
        package_version=$(lookup "package-$(field .php_package)" scripts/php-package-version.sh "$(field .php_package)")
        args+=(--build-arg "PHP_PACKAGE_VERSION=$package_version")
        args+=(--label "hr.maidea.php-package=$(field .php_package)=$package_version")
    fi
    tags=()
    while IFS= read -r t; do tags+=("$REPO:$t"); done < <(field '.tags[]')
    for t in "${tags[@]}"; do args+=(-t "$t"); done

    echo "::group::build $id"
    docker buildx build "${args[@]}" "$(field .context)"
    echo "::endgroup::"

    # x.y.z without a distribution suffix (Debian's PHP_VERSION is e.g. 5.6.40-105+0~...)
    php_version=$(docker run --rm --platform "$PLATFORM" "${tags[0]}" php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION, ".", PHP_RELEASE_VERSION;')
    # The built PHP version must be the one of its source: the PHP package, or the official php base image
    if [ "$(field .php_package)" != null ]; then
        source="$(field .php_package) $package_version"
        upstream=$(sed -E 's/^[0-9]+://; s/-.*$//' <<< "$package_version")
    else
        # PHP_VERSION of the base image, which the image inherits
        source="$(field .base)@$base_amd64"
        upstream=$(docker image inspect "${tags[0]}" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^PHP_VERSION=//p')
    fi
    [ "$php_version" = "$upstream" ] || { echo "$id: built PHP $php_version, but $source is PHP $upstream" >&2; exit 1; }
    if [ "$(field .immutable_prefix)" != null ]; then
        # Immutable tags are never overwritten: if the name already exists (e.g. a second build that day), add .2, .3, ...
        immutable="$REPO:$(field .immutable_prefix)$php_version-$DATE" n=1
        while tag_exists "${immutable#"$REPO":}"; do
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
