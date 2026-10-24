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
    args=(--platform "$PLATFORM" --load --pull)
    [ "$(field .target)" != null ] && args+=(--target "$(field .target)")
    while IFS= read -r kv; do args+=(--build-arg "$kv"); done < <(field '.args | to_entries[] | "\(.key)=\(.value)"')
    # Recorded so the upstream check can tell when the base image has changed
    base_digest=$(docker buildx imagetools inspect "$(field .base)" --format '{{json .Manifest.Digest}}' | tr -d '"')
    args+=(--label "org.opencontainers.image.base.name=docker.io/library/$(field .base)")
    args+=(--label "org.opencontainers.image.base.digest=$base_digest")
    if [ "$(field .php_package)" != null ]; then
        # PHP from a package (legacy images): build its current version and record it for the upstream check
        package_version=$(scripts/php-package-version.sh "$(field .php_package)")
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
        source=$(field .base)
        upstream=$(docker buildx imagetools inspect "$(field .base)" --format '{{json .Image}}' \
            | jq -r '."linux/amd64".config.Env[] | select(startswith("PHP_VERSION=")) | sub("PHP_VERSION="; "")')
    fi
    [ "$php_version" = "$upstream" ] || { echo "$id: built PHP $php_version, but $source is PHP $upstream" >&2; exit 1; }
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
