#!/bin/sh
set -eu

endpoint="${1:-}"
interval="${2:-10}"
startup_timeout="${3:-180}"
health_port="${4:-8080}"
health_dir="/tmp/echo-client-health"
health_status="$health_dir/status"
health_body="$health_dir/body.json"

if [ -z "$endpoint" ]; then
    echo "usage: echo-client <endpoint> [interval_seconds] [startup_timeout_seconds] [health_port]" >&2
    exit 2
fi

validate_positive_integer() {
    name="$1"
    value="$2"

    case "$value" in
        ''|*[!0-9]*)
            echo "$name must be a positive integer number of seconds" >&2
            exit 2
            ;;
        0)
            echo "$name must be greater than zero" >&2
            exit 2
            ;;
    esac
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_health() {
    status_code="$1"
    healthy="$2"
    reason="$3"
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason_json="$(json_escape "$reason")"
    endpoint_json="$(json_escape "$endpoint")"

    mkdir -p "$health_dir"
    printf '%s\n' "$status_code" >"$health_status.tmp"
    cat >"$health_body.tmp" <<JSON
{"healthy":$healthy,"endpoint":"$endpoint_json","reason":"$reason_json","time":"$now"}
JSON
    mv "$health_status.tmp" "$health_status"
    mv "$health_body.tmp" "$health_body"
}

write_health_responder() {
    mkdir -p "$health_dir"
    cat >"$health_dir/respond" <<'RESPONDER'
#!/bin/sh
health_dir="/tmp/echo-client-health"
health_status="$health_dir/status"
health_body="$health_dir/body.json"

request_line=""
IFS= read -r request_line || true
while IFS= read -r header; do
    [ "$header" = "$(printf '\r')" ] || [ -z "$header" ] && break
done

path="$(printf '%s' "$request_line" | awk '{print $2}' | tr -d '\r')"
stored_status="$(cat "$health_status" 2>/dev/null || printf '503')"
if [ "$path" = "/validate" ]; then
    status_code="200"
    reason="OK"
    content_type="text/plain"
    if [ "$stored_status" = "200" ]; then
        body="healthy"
    else
        body="unhealthy"
    fi
elif [ "$path" = "/health" ] || [ "$path" = "/healthz" ] || [ "$path" = "/" ]; then
    status_code="$stored_status"
    content_type="application/json"
    body="$(cat "$health_body" 2>/dev/null || printf '{"healthy":false,"reason":"starting"}')"
    if [ "$status_code" = "200" ]; then
        reason="OK"
    else
        reason="Service Unavailable"
    fi
else
    status_code="404"
    reason="Not Found"
    content_type="application/json"
    body='{"healthy":false,"reason":"not found"}'
fi

printf 'HTTP/1.1 %s %s\r\n' "$status_code" "$reason"
printf 'Content-Type: %s\r\n' "$content_type"
printf 'Content-Length: %s\r\n' "$(printf '%s' "$body" | wc -c)"
printf 'Connection: close\r\n\r\n'
printf '%s' "$body"
RESPONDER
    chmod 0755 "$health_dir/respond"
}

health_server() {
    write_health_responder
    socat "TCP-LISTEN:${health_port},reuseaddr,fork" "EXEC:${health_dir}/respond"
}

validate_positive_integer "interval" "$interval"
validate_positive_integer "startup timeout" "$startup_timeout"
validate_positive_integer "health port" "$health_port"

write_health 503 false "starting"
health_server &
health_pid="$!"
trap 'kill "$health_pid" 2>/dev/null || true' EXIT INT TERM

curl_endpoint() {
    curl --fail --silent --show-error --location --max-time 10 "$endpoint" >/dev/null
}

echo "Waiting up to ${startup_timeout}s for $endpoint"
deadline=$(( $(date +%s) + startup_timeout ))

while ! curl_endpoint; do
    now="$(date +%s)"
    if [ "$now" -ge "$deadline" ]; then
        write_health 503 false "endpoint did not become ready within ${startup_timeout}s"
        echo "Endpoint did not become ready within ${startup_timeout}s: $endpoint" >&2
        while :; do sleep "$interval"; done
    fi
    write_health 503 false "waiting for endpoint"
    sleep "$interval"
done

write_health 200 true "endpoint ready"
echo "Endpoint ready: $endpoint"

while :; do
    sleep "$interval"
    if curl_endpoint; then
        write_health 200 true "endpoint reachable"
    else
        write_health 503 false "endpoint check failed"
        echo "Endpoint check failed: $endpoint" >&2
    fi
done
