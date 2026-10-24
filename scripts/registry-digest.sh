#!/usr/bin/env bash
# Print the current digest of a Docker Hub image (e.g. php:8.4-apache-bookworm) with a HEAD request,
# which Docker Hub does not count as a pull. Uses the Docker Hub login (credential helper or config.json), if any.
# Usage: scripts/registry-digest.sh <image:tag>
set -eo pipefail

name=${1%:*} tag=${1##*:}
[ "$name" != "${name#*/}" ] || name=library/$name

# Credentials of `docker login`, passed to curl through stdin (not visible in the process list)
cfg=${DOCKER_CONFIG:-$HOME/.docker}/config.json userpass=
if [ -f "$cfg" ]; then
    store=$(jq -r '.credsStore // empty' "$cfg")
    if [ -n "$store" ]; then
        cred=$(echo https://index.docker.io/v1/ | "docker-credential-$store" get 2>/dev/null || true)
        [ -z "$cred" ] || userpass="$(jq -r .Username <<< "$cred"):$(jq -r .Secret <<< "$cred")"
    else
        auth=$(jq -r '.auths["https://index.docker.io/v1/"].auth // empty' "$cfg")
        [ -z "$auth" ] || userpass=$(base64 -d <<< "$auth")
    fi
fi
url="https://auth.docker.io/token?service=registry.docker.io&scope=repository:$name:pull"
if [ -n "$userpass" ]; then
    token=$(printf 'user = "%s"\n' "$userpass" | curl -fsS -K - "$url" | jq -r .token)
else
    token=$(curl -fsS "$url" | jq -r .token)
fi

curl -fsS --head -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://registry-1.docker.io/v2/$name/manifests/$tag" \
    | awk 'tolower($1) == "docker-content-digest:" { print $2 }' | tr -d '\r' | grep . \
    || { echo "no digest for $1" >&2; exit 1; }
