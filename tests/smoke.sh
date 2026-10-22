#!/usr/bin/env bash
# Smoke-test an image: what the image promises, checked through a running container.
# Usage: tests/smoke.sh <image> <prod|dev|legacy> <php minor, e.g. 8.4>
set -o pipefail

IMAGE=$1 KIND=$2 PHP=$3
FIXTURES="$(cd "$(dirname "$0")" && pwd)/fixtures/webroot"
P=(--platform linux/amd64)
NET="smoke-net-$$" NAME="smoke-target-$$"
fail=0

pass() { echo "  PASS  $1"; }
check() { # check <description> <actual> <expected>
    if [ "$2" = "$3" ]; then pass "$1 = $3"; else echo "  FAIL  $1: got '$2', want '$3'"; fail=1; fi
}
json() { python3 -I -c "import sys,json; print(json.load(sys.stdin).get('$1'))"; }

echo "== smoke $IMAGE ($KIND, PHP $PHP)"
check "architecture" "$(docker image inspect -f '{{.Architecture}}' "$IMAGE")" amd64
version=$(docker run --rm "${P[@]}" "$IMAGE" php -r 'echo PHP_VERSION;')
check "PHP $PHP.x" "${version%.*}" "$PHP"

docker network create "$NET" >/dev/null
cid=$(docker run -d "${P[@]}" --network "$NET" --name "$NAME" -v "$FIXTURES:/src:ro" "$IMAGE")
trap 'docker rm -f "$cid" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1' EXIT
inside() { docker exec "$cid" "$@"; }

if [ "$KIND" = legacy ]; then
    sleep 5
    probe=$(inside curl -s http://localhost/)
    check "PHP served by Apache" "$(echo "$probe" | json php)" "$version"
    check "CVE-2026-109618/109619 patch in image" \
        "$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$IMAGE" | grep '^PHP_PATCHES=')" "PHP_PATCHES=CVE-2026-109618-109619"
    check "session upload progress off" "$(echo "$probe" | json upload_progress)" 0
    check "upload_max_filesize" "$(echo "$probe" | json upload_max_filesize)" 100M
    check "post_max_size" "$(echo "$probe" | json post_max_size)" 110M
    check "max_input_nesting_level" "$(echo "$probe" | json max_input_nesting_level)" 16
    check "memory_limit default (overridable by apps)" \
        "$(echo "$probe" | json memory_limit)/$(echo "$probe" | json memory_limit_overridable)" "1024M/True"
    check "one request per process (Connection: close)" \
        "$(inside curl -sI http://localhost/ | grep -i '^connection:' | tr -d '\r' | tr '[:upper:]' '[:lower:]')" "connection: close"
    check "request body over 110M rejected" \
        "$(inside sh -c 'head -c 120000000 /dev/zero | curl -s -o /dev/null -w "%{http_code}" --max-time 20 --data-binary @- http://localhost/')" 413
    mem=$(docker run -d "${P[@]}" -e PHP_MEMORY_LIMIT=-1 -v "$FIXTURES:/src:ro" "$IMAGE"); sleep 5
    probe=$(docker exec "$mem" curl -s http://localhost/); docker rm -f "$mem" >/dev/null
    check "PHP_MEMORY_LIMIT=-1 (locked)" \
        "$(echo "$probe" | json memory_limit)/$(echo "$probe" | json memory_limit_overridable)" "-1/False"
    [ $fail = 0 ] && echo "  RESULT: ALL PASS" || echo "  RESULT: FAILURES"
    exit $fail
fi

check "CLI argv" "$(docker run --rm "${P[@]}" "$IMAGE" php -r 'echo $argv[1];' -- hello)" hello
check "wkhtmltopdf renders a PDF" \
    "$(docker run --rm "${P[@]}" "$IMAGE" sh -c 'echo "<h1>smoke</h1>" > /tmp/a.html && wkhtmltopdf -q /tmp/a.html /tmp/a.pdf >/dev/null 2>&1; head -c 5 /tmp/a.pdf')" "%PDF-"

for _ in $(seq 1 40); do
    health=$(docker inspect -f '{{.State.Health.Status}}' "$cid")
    [ "$health" = healthy ] && break
    sleep 2
done
check "docker health status" "$health" healthy
check "health probe" "$(inside curl -fsS http://127.0.0.1:8081/)" ok
check "health port unreachable from other containers" \
    "$(docker run --rm "${P[@]}" --network "$NET" curlimages/curl:8.10.1 -s -o /dev/null -w '%{http_code}' --max-time 3 "http://$NAME:8081/" 2>/dev/null)" 000
check ".htaccess rewrite" "$(inside curl -s -o /dev/null -w '%{http_code}' http://localhost/rw-test)" 200
check "mod_headers via .htaccess" "$(inside curl -sI http://localhost/rw-test | grep -i '^x-smoke-header' | tr -d '\r')" "X-Smoke-Header: yes"
check "no directory listing" "$(inside curl -s -o /dev/null -w '%{http_code}' http://localhost/dir/)" 403

probe=$(inside curl -s http://localhost/)
check "APCu through Apache" "$(echo "$probe" | json apcu_roundtrip)" True
check "decimal through Apache" "$(echo "$probe" | json decimal)" 0.3
check "imap available" "$(echo "$probe" | json imap)" True
check "health checks not in access log" "$(docker logs "$cid" 2>&1 | grep -c ':8081')" 0

if [ "$KIND" = prod ]; then
    headers=$(inside curl -sI http://localhost/)
    check "no X-Powered-By header" "$(echo "$headers" | grep -ci '^x-powered-by')" 0
    check "Server header" "$(echo "$headers" | grep -i '^server:' | tr -d '\r')" "Server: Apache"
    check "query string does not populate argv" "$(inside curl -s 'http://localhost/argv.php?+config-create+/x')" argv-absent
else
    check "xdebug loaded" "$(docker run --rm "${P[@]}" -e XDEBUG_MODE=off "$IMAGE" php -r 'echo extension_loaded("xdebug") ? "yes" : "no";')" yes
    check "composer runs" "$(docker run --rm "${P[@]}" "$IMAGE" sh -c 'composer --version --no-ansi 2>/dev/null | grep -c "^Composer version"')" 1
fi

[ $fail = 0 ] && echo "  RESULT: ALL PASS" || echo "  RESULT: FAILURES"
exit $fail
