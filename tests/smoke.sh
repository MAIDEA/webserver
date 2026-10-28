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
ready() { # ready <container>: wait until Apache answers (up to 30 s)
    for _ in $(seq 1 60); do docker exec "$1" curl -fs -o /dev/null http://localhost/ 2>/dev/null && return; sleep 0.5; done
}

echo "== smoke $IMAGE ($KIND, PHP $PHP)"
check "architecture" "$(docker image inspect -f '{{.Architecture}}' "$IMAGE")" amd64

# One container for most checks (command-line checks run in it too, instead of starting a container each)
docker network create "$NET" >/dev/null
cid=$(docker run -d "${P[@]}" --network "$NET" --name "$NAME" -v "$FIXTURES:/src:ro" "$IMAGE")
trap 'docker rm -f "$cid" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1' EXIT
inside() { docker exec "$cid" "$@"; }
version=$(inside php -r 'echo PHP_VERSION;')
check "PHP $PHP.x" "$(inside php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;')" "$PHP"

# All images: health check, reverse proxies, entrypoint (WWW_DATA_UID/GID, PHP_INI_*, /docker-entrypoint.d/)
for _ in $(seq 1 40); do
    health=$(docker inspect -f '{{.State.Health.Status}}' "$cid")
    [ "$health" = healthy ] && break
    sleep 2
done
check "docker health status" "$health" healthy
check "health probe" "$(inside curl -fsS http://127.0.0.1:8081/)" ok
check "health port unreachable from other containers" \
    "$(docker run --rm "${P[@]}" --network "$NET" --entrypoint curl "$IMAGE" -s -o /dev/null -w '%{http_code}' --max-time 3 "http://$NAME:8081/" 2>/dev/null)" 000
probe=$(inside curl -s -H 'X-Forwarded-For: 203.0.113.7' -H 'X-Forwarded-Proto: https' http://localhost/)
check "client IP from a trusted proxy" "$(echo "$probe" | json remote_addr)" 203.0.113.7
check "HTTPS from a trusted proxy" "$(echo "$probe" | json https)" on
check "client IP in access log" "$(docker logs "$cid" 2>/dev/null | grep -c '^203\.0\.113\.7 ')" 1
check "health checks not in access log" "$(docker logs "$cid" 2>&1 | grep -c ':8081')" 0
check "hidden file not served (.env)" "$(inside curl -s -o /dev/null -w '%{http_code}' http://localhost/.env)" 403
check "hidden folder not served" "$(inside curl -s -o /dev/null -w '%{http_code}' http://localhost/.private/secret.txt)" 403
check ".well-known served" "$(inside curl -s http://localhost/.well-known/test.txt)" ok
check "nosniff header" "$(inside curl -sI http://localhost/ | grep -i '^x-content-type-options' | tr -d '\r')" "X-Content-Type-Options: nosniff"
check "no server-status page" "$(inside curl -s -o /dev/null -w '%{http_code}' http://localhost/server-status)" 404
env=$(docker run -d "${P[@]}" -v "$FIXTURES:/src:ro" -v "$(dirname "$FIXTURES")/entrypoint.d:/docker-entrypoint.d:ro" \
    -e WWW_DATA_UID=1234 -e WWW_DATA_GID=1234 -e PHP_INI_MAX_EXECUTION_TIME=77 -e APACHE_TRUSTED_PROXIES=none \
    -e PHP_INI_POST_MAX_SIZE=1M -e APACHE_MAX_REQUEST_WORKERS=7 "$IMAGE")
ready "$env"
probe=$(docker exec "$env" curl -s -H 'X-Forwarded-For: 203.0.113.7' http://localhost/)
check "WWW_DATA_UID (Apache's user)" "$(echo "$probe" | json euid)" 1234
check "PHP_INI_MAX_EXECUTION_TIME" "$(echo "$probe" | json max_execution_time)" 77
check "APACHE_TRUSTED_PROXIES=none" "$(echo "$probe" | json remote_addr)" 127.0.0.1
check "startup hook ran" "$(docker exec "$env" cat /tmp/hook-ran)" "hook ran"
if [ "$KIND" != legacy ]; then  # legacy images keep a fixed 110M limit
    check "request body over post_max_size + 10% rejected" \
        "$(docker exec "$env" sh -c 'head -c 2000000 /dev/zero | curl -s -o /dev/null -w "%{http_code}" --data-binary @- http://localhost/')" 413
fi
docker rm -f "$env" >/dev/null

# Extensions: the same set in every image (apart from what a PHP version cannot have), loaded by Apache as on the command line
want="bcmath exif ftp gd imap intl mysqli pdo_mysql shmop soap sockets zip" cli_only=readline
if [ "$KIND" = legacy ]; then cli_only=pcntl; else want="$want apcu decimal pcntl pdo_pgsql pgsql"; fi
web_ext=$(inside curl -s http://localhost/extensions.php | grep -v -x apache2handler | LC_ALL=C sort)
cli_ext=$(inside php -m | grep -v -e '^\[' -e '^$' | tr '[:upper:]' '[:lower:]' | LC_ALL=C sort -u)
missing=$(for e in $want; do echo "$web_ext" | grep -qx "$e" || printf '%s ' "$e"; done)
check "extensions in Apache ($want)" "${missing:-all}" all
check "Apache loads the command line's extensions, except $cli_only" \
    "$(diff <(echo "$web_ext") <(echo "$cli_ext") | grep '^[<>]' | tr '\n' ' ')" "> $cli_only "
check "FTP over SSL" "$(inside php -r 'echo function_exists("ftp_ssl_connect") ? "yes" : "no";')" yes

if [ "$KIND" = legacy ]; then
    check "Debian's conf.d directories are links to the one PHP reads" \
        "$(inside sh -c 'readlink /etc/php/*/apache2/conf.d /etc/php/*/cli/conf.d' | sort -u)" /usr/local/etc/php/conf.d
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
    mem=$(docker run -d "${P[@]}" -e PHP_MEMORY_LIMIT=-1 -v "$FIXTURES:/src:ro" "$IMAGE"); ready "$mem"
    probe=$(docker exec "$mem" curl -s http://localhost/); docker rm -f "$mem" >/dev/null
    check "PHP_MEMORY_LIMIT=-1 (locked)" \
        "$(echo "$probe" | json memory_limit)/$(echo "$probe" | json memory_limit_overridable)" "-1/False"
    [ $fail = 0 ] && echo "  RESULT: ALL PASS" || echo "  RESULT: FAILURES"
    exit $fail
fi

# shellcheck disable=SC2016
check "CLI argv" "$(inside php -r 'echo $argv[1];' -- hello)" hello
check "wkhtmltopdf renders a PDF" \
    "$(inside sh -c 'echo "<h1>smoke</h1>" > /tmp/a.html && wkhtmltopdf -q /tmp/a.html /tmp/a.pdf >/dev/null 2>&1; head -c 5 /tmp/a.pdf')" "%PDF-"

check ".htaccess rewrite" "$(inside curl -s -o /dev/null -w '%{http_code}' http://localhost/rw-test)" 200
check "mod_headers via .htaccess" "$(inside curl -sI http://localhost/rw-test | grep -i '^x-smoke-header' | tr -d '\r')" "X-Smoke-Header: yes"
check "no directory listing" "$(inside curl -s -o /dev/null -w '%{http_code}' http://localhost/dir/)" 403

probe=$(inside curl -s http://localhost/)
check "APCu through Apache" "$(echo "$probe" | json apcu_roundtrip)" True
check "decimal through Apache" "$(echo "$probe" | json decimal)" 0.3
check "imap available" "$(echo "$probe" | json imap)" True
check "session upload progress off" "$(echo "$probe" | json upload_progress)" 0

if [ "$KIND" = prod ]; then
    headers=$(inside curl -sI http://localhost/)
    check "no X-Powered-By header" "$(echo "$headers" | grep -ci '^x-powered-by')" 0
    check "Server header" "$(echo "$headers" | grep -i '^server:' | tr -d '\r')" "Server: Apache"
    check "query string does not populate argv" "$(inside curl -s 'http://localhost/argv.php?+config-create+/x')" argv-absent
    check "prod PHP settings (JIT, SameSite, exception args)" \
        "$(inside php -r 'echo ini_get("opcache.jit"), "/", ini_get("session.cookie_samesite"), "/", ini_get("zend.exception_ignore_args");')" "disable/Lax/1"
else
    check "xdebug loaded" "$(docker exec -e XDEBUG_MODE=off "$cid" php -r 'echo extension_loaded("xdebug") ? "yes" : "no";')" yes
    check "composer runs" "$(inside sh -c 'composer --version --no-ansi 2>/dev/null | grep -c "^Composer version"')" 1
fi

[ $fail = 0 ] && echo "  RESULT: ALL PASS" || echo "  RESULT: FAILURES"
exit $fail
