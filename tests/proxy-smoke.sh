#!/bin/sh
set -eu

if [ "${1:-}" != --disposable-openwrt ]; then
	printf '%s\n' 'Run only in a disposable OpenWrt test environment: sh proxy-smoke.sh --disposable-openwrt' >&2
	exit 2
fi

runtime=/var/run/exconnect
config=/etc/config/exconnect
[ ! -e "$runtime/config.json" ] || { printf '%s\n' 'ExConnect has already been configured.' >&2; exit 1; }
fixture=$(mktemp -d)
httpd_pid=
upstream_pid=
client_pid=

cleanup() {
	for pid in "$client_pid" "$upstream_pid" "$httpd_pid"; do
		[ -n "$pid" ] || continue
		kill "$pid" 2>/dev/null || :
		wait "$pid" 2>/dev/null || :
	done
	if [ -f "$fixture/original-config" ]; then
		cat "$fixture/original-config" > "$config"
	fi
	rm -f "$runtime/config.json" "$runtime/lan.nft" "$runtime/last_error"
	rm -rf "$fixture"
}

fail() {
	printf '%s\n' "$*" >&2
	for log in "$fixture"/*.log; do
		[ ! -f "$log" ] || cat "$log" >&2
	done
	exit 1
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mkdir "$fixture/www"
printf '%s\n' 'ExConnect proxy smoke fixture' > "$fixture/www/probe.txt"

cat > "$fixture/upstream.json" <<'EOF'
{
  "inbounds": [{
    "port": 17882, "listen": "127.0.0.1", "protocol": "socks",
    "settings": {"auth": "password", "accounts": [{"user": "fixture", "pass": "test-only"}]}
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

cp "$config" "$fixture/original-config"
cat > "$config" <<'EOF'
config service 'main'
	option enabled '1'
	option mode 'local'
	option profile 'upstream'
	option socks_port '17880'
	option http_port '17881'
	option default_action 'proxy'
config profile 'upstream'
	option uri 'socks5://fixture:test-only@127.0.0.1:17882'
EOF

/usr/libexec/exconnect/control prepare > "$fixture/prepare.log" 2>&1 || fail 'ExConnect could not prepare its configuration.'

uhttpd -f -p 127.0.0.1:17883 -h "$fixture/www" > "$fixture/uhttpd.log" 2>&1 &
httpd_pid=$!
xray run -config "$fixture/upstream.json" > "$fixture/upstream.log" 2>&1 &
upstream_pid=$!
/usr/libexec/exconnect/run > "$fixture/client.log" 2>&1 &
client_pid=$!

url=http://127.0.0.1:17883/probe.txt
probe() {
	curl -q -fsS --connect-timeout 2 --max-time 3 --noproxy '' --proxy "$1" "$url" > "$fixture/response"
}

for proxy in http://127.0.0.1:17881 socks5h://127.0.0.1:17880; do
	attempt=0
	until [ -s "$runtime/ready" ] && probe "$proxy" 2> "$fixture/curl.log"; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt 10 ] || fail "No response through $proxy."
		kill -0 "$httpd_pid" "$upstream_pid" "$client_pid" 2>/dev/null || fail 'A test process exited.'
		sleep 1
	done
	cmp "$fixture/www/probe.txt" "$fixture/response" || fail "Unexpected response through $proxy."
done

kill "$upstream_pid"
wait "$upstream_pid" || :
upstream_pid=

# Keep the HTTP origin live while proving the proxy cannot bypass its configured upstream.
probe '' || fail 'The test HTTP origin stopped responding.'
for proxy in http://127.0.0.1:17881 socks5h://127.0.0.1:17880; do
	if probe "$proxy" 2> "$fixture/curl.log"; then
		fail "Traffic through $proxy bypassed the stopped upstream."
	fi
done
kill -0 "$client_pid" 2>/dev/null || fail 'The ExConnect Xray client stopped unexpectedly.'

printf '%s\n' 'HTTP and SOCKS traffic passed through the configured Xray upstream.'
