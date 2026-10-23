#!/usr/bin/env bash
# Smoke test for the PHP 7.4 FPM image.
#
# Usage: tests/smoke.sh [IMAGE] [EXPECTED_VERSION]
#   IMAGE            image reference to test (default: docker-ondrej-php:7.4-test)
#   EXPECTED_VERSION major.minor the image must report (default: 7.4)
#
# Runs the same assertions locally and in CI.

set -euo pipefail

IMAGE="${1:-docker-ondrej-php:7.4-test}"
EXPECTED_VERSION="${2:-7.4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    ENGINE=docker
elif command -v podman >/dev/null 2>&1; then
    ENGINE=podman
else
    echo "FAIL: neither a working docker daemon nor podman is available" >&2
    exit 1
fi

NAME="ondrej-php-smoke-$$"

cleanup() {
    "$ENGINE" rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    echo "--- container logs ---" >&2
    "$ENGINE" logs "$NAME" >&2 2>&1 || true
    exit 1
}

pass() {
    echo "ok - $*"
}

in_container() {
    "$ENGINE" exec "$NAME" "$@"
}

echo "engine: $ENGINE"
echo "image:  $IMAGE"

"$ENGINE" run -d --name "$NAME" -p 127.0.0.1::9000 "$IMAGE" >/dev/null

# --- the container stays up -------------------------------------------------
sleep 1
state=$("$ENGINE" inspect --format '{{.State.Running}}' "$NAME")
[ "$state" = "true" ] || fail "container is not running (PHP-FPM daemonized or crashed)"

pid1=$(in_container sh -c 'tr "\0" " " < /proc/1/cmdline') || fail "cannot read PID 1"
case "$pid1" in
    *php-fpm*master*) pass "php-fpm runs in the foreground as PID 1" ;;
    *) fail "PID 1 is not the php-fpm master: $pid1" ;;
esac

# --- php --------------------------------------------------------------------
version=$(in_container php -r 'echo PHP_VERSION;') || fail "php is not executable"
case "$version" in
    "$EXPECTED_VERSION".*) pass "php reports $version" ;;
    *) fail "php reports $version, expected $EXPECTED_VERSION.x" ;;
esac

fpm_bin=$(in_container sh -c 'command -v php-fpm') || fail "php-fpm is not on PATH"
pass "php-fpm resolves to $fpm_bin"

in_container "php-fpm${EXPECTED_VERSION}" -t >/dev/null 2>&1 \
    || fail "php-fpm configuration test failed"
pass "php-fpm configuration test passes"

# --- both listeners ---------------------------------------------------------
in_container test -S "/run/php/php${EXPECTED_VERSION}-fpm.sock" \
    || fail "unix socket /run/php/php${EXPECTED_VERSION}-fpm.sock is missing"
pass "unix socket listener is present"

mapping=$("$ENGINE" port "$NAME" 9000/tcp | head -n1)
port="${mapping##*:}"
[ -n "$port" ] || fail "port 9000/tcp is not published"

for _ in $(seq 1 50); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
        exec 3>&-
        break
    fi
    sleep 0.2
done
(exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null || fail "TCP 9000 is not accepting connections"
exec 3>&-
pass "TCP listener accepts connections on host port $port"

# --- a real FastCGI request -------------------------------------------------
printf '%s\n' '<?php echo "SMOKE=" . PHP_VERSION;' \
    | "$ENGINE" exec -i "$NAME" tee /var/www/html/index.php >/dev/null

if command -v python3 >/dev/null 2>&1; then
    response=$(python3 "$SCRIPT_DIR/fcgi_client.py" 127.0.0.1 "$port" /var/www/html/index.php) \
        || fail "FastCGI client failed"
elif command -v cgi-fcgi >/dev/null 2>&1; then
    response=$(SCRIPT_FILENAME=/var/www/html/index.php REQUEST_METHOD=GET \
        cgi-fcgi -bind -connect "127.0.0.1:$port") || fail "cgi-fcgi failed"
else
    fail "neither python3 nor cgi-fcgi is available to issue a FastCGI request"
fi

case "$response" in
    *"SMOKE=$EXPECTED_VERSION".*) pass "FastCGI request returned PHP $EXPECTED_VERSION" ;;
    *) fail "unexpected FastCGI response: $response" ;;
esac

# --- graceful shutdown ------------------------------------------------------
"$ENGINE" stop -t 10 "$NAME" >/dev/null || fail "container did not stop cleanly"
exit_code=$("$ENGINE" inspect --format '{{.State.ExitCode}}' "$NAME")
[ "$exit_code" = "0" ] || fail "container exited with code $exit_code on SIGQUIT"
pass "container stops cleanly on SIGQUIT"

echo
echo "PASS: $IMAGE"
