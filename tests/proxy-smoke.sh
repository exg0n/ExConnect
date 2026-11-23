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

check_diagnostics() {
	kind=$1
	expected_speed=${2:-8}
	expected_bytes=${3:-2000000}
	printf '{"section":"upstream","kind":"%s"}\n' "$kind" |
		EXCONNECT_PROBE_FIXTURE="$fixture" PATH="$fixture/probe-tools:$PATH" \
			/usr/libexec/rpcd/exconnect call probe > "$fixture/probe-result.json"
	if [ "$(jsonfilter -i "$fixture/probe-result.json" -e '@.ok')" != true ]; then
		cat "$fixture/probe-result.json" >&2
		fail "Could not test $kind through the isolated profile."
	fi
	if [ "$kind" = latency ]; then
		[ "$(jsonfilter -i "$fixture/probe-result.json" -e '@.latency_ms')" -eq 125 ]
	else
		value=$(jsonfilter -i "$fixture/probe-result.json" -e '@.speed_mbps')
		awk -v value="$value" -v expected="$expected_speed" 'BEGIN { exit !(value == expected) }'
		[ "$(jsonfilter -i "$fixture/probe-result.json" -e '@.bytes')" -eq "$expected_bytes" ]
	fi
	port=$(cat "$fixture/probe-port")
	[ -z "$(ss -H -ltn "sport = :$port")" ] || fail 'The temporary diagnostic listener was left open.'
}

mkdir "$fixture/probe-tools"
cat > "$fixture/probe-tools/curl" <<'EOF'
#!/bin/sh
set -eu
proxy=
url=
while [ "$#" -gt 0 ]; do
	case "$1" in
		--proxy) proxy=$2; shift ;;
		https://speed.cloudflare.com/*) url=$1 ;;
	esac
	shift
done
case "$proxy" in
	socks5h://127.0.0.1:*) port=${proxy##*:} ;;
	*) exit 1 ;;
esac
[ "$port" != 17880 ]
[ "$port" -ge 18900 ] && [ "$port" -le 18915 ]
[ -n "$(ss -H -ltn "sport = :$port")" ]
printf '%s\n' "$port" > "$EXCONNECT_PROBE_FIXTURE/probe-port"
/usr/bin/curl -q -fsS --connect-timeout 2 --max-time 3 --noproxy '' \
	--proxy "$proxy" http://127.0.0.1:17883/probe.txt \
	> "$EXCONNECT_PROBE_FIXTURE/probe-response"
cmp "$EXCONNECT_PROBE_FIXTURE/www/probe.txt" "$EXCONNECT_PROBE_FIXTURE/probe-response"
case "$url" in
	*'?bytes=0') printf '200 0.125000 0 0\n' ;;
	*'?bytes=2000000')
		if [ -e "$EXCONNECT_PROBE_FIXTURE/probe-partial-speed" ]; then
			printf '200 0.125000 10000 120000\n'
			exit 28
		fi
		printf '200 0.125000 1000000 2000000\n'
		;;
	*) exit 1 ;;
esac
EOF
cat > "$fixture/probe-tools/logread" <<'EOF'
#!/bin/sh
printf '%s\n' \
	'Sun Nov 22 15:10:00 2026 daemon.info exconnect: Loading hy2://fake-test-password@example.test' \
	'Sun Nov 22 15:10:01 2026 daemon.err exconnect-core[1024]: Expected core event' \
	'Sun Nov 22 15:10:02 2026 daemon.info unrelated: ExConnect should ignore this event'
EOF
chmod 700 "$fixture/probe-tools/curl" "$fixture/probe-tools/logread"

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

uhttpd -f -p 127.0.0.1:17883 -h "$fixture/www" > "$fixture/uhttpd.log" 2>&1 &
httpd_pid=$!
xray run -config "$fixture/upstream.json" > "$fixture/upstream.log" 2>&1 &
upstream_pid=$!
attempt=0
until [ -n "$(ss -H -ltn 'sport = :17882')" ] &&
	curl -q -fsS --connect-timeout 2 --max-time 3 --noproxy '*' \
		http://127.0.0.1:17883/probe.txt > "$fixture/response" 2> "$fixture/curl.log"; do
	attempt=$((attempt + 1))
	[ "$attempt" -lt 10 ] || fail 'The diagnostic test servers did not start.'
	kill -0 "$httpd_pid" "$upstream_pid" 2>/dev/null || fail 'A test server exited.'
	sleep 1
done
cmp "$fixture/www/probe.txt" "$fixture/response"

check_diagnostics latency
[ ! -e "$runtime/ready" ]
PATH="$fixture/probe-tools:$PATH" /usr/libexec/rpcd/exconnect call logs > "$fixture/log-result.json"
[ "$(jsonfilter -i "$fixture/log-result.json" -e '@.ok')" = true ]
log=$(jsonfilter -i "$fixture/log-result.json" -e '@.log')
printf '%s\n' "$log" | grep -Fq 'Expected core event'
printf '%s\n' "$log" | grep -Fq 'hy2://[redacted]'
if printf '%s\n' "$log" | grep -Eq 'fake-test-password|unrelated'; then
	fail 'The ExConnect log exposed unrelated content or a profile link.'
fi

/usr/libexec/exconnect/control prepare > "$fixture/prepare.log" 2>&1 || fail 'ExConnect could not prepare its configuration.'

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

check_diagnostics speed
touch "$fixture/probe-partial-speed"
check_diagnostics speed 0.08 120000
rm "$fixture/probe-partial-speed"
[ -s "$runtime/ready" ]
kill -0 "$client_pid"
probe http://127.0.0.1:17881

# A missing DAT file must produce a useful error while the active service stays live.
uci set exconnect.missing_data=rule
uci set exconnect.missing_data.action=direct
uci add_list 'exconnect.missing_data.domains=ext:exconnect-test-missing.dat:fixture'
uci commit exconnect
printf '%s\n' '{}' | /usr/libexec/rpcd/exconnect call validate > "$fixture/validation-result.json"
[ "$(jsonfilter -i "$fixture/validation-result.json" -e '@.ok')" = false ] ||
	fail 'Validation accepted a missing rule data file.'
error=$(jsonfilter -i "$fixture/validation-result.json" -e '@.error')
printf '%s\n' "$error" | grep -Fq 'exconnect-test-missing.dat is missing'
printf '%s\n' "$error" | grep -Fq 'Download the configured files in Rule data'
uci delete exconnect.missing_data.domains
uci add_list exconnect.missing_data.ips=telegram
uci commit exconnect
printf '%s\n' '{}' | /usr/libexec/rpcd/exconnect call validate > "$fixture/validation-result.json"
[ "$(jsonfilter -i "$fixture/validation-result.json" -e '@.ok')" = false ] ||
	fail 'Validation accepted an invalid IP selector.'
error=$(jsonfilter -i "$fixture/validation-result.json" -e '@.error')
printf '%s\n' "$error" | grep -Fq 'invalid IP: telegram'
uci delete exconnect.missing_data
uci commit exconnect
[ -s "$runtime/ready" ]
kill -0 "$client_pid"
probe http://127.0.0.1:17881

kill "$upstream_pid"
wait "$upstream_pid" || :
upstream_pid=

# Keep the HTTP origin live while proving the proxy cannot bypass its configured upstream.
probe '' || fail 'The test HTTP origin stopped responding.'
printf '%s\n' '{"section":"upstream","kind":"latency"}' |
	EXCONNECT_PROBE_FIXTURE="$fixture" PATH="$fixture/probe-tools:$PATH" \
		/usr/libexec/rpcd/exconnect call probe > "$fixture/probe-result.json"
[ "$(jsonfilter -i "$fixture/probe-result.json" -e '@.ok')" = false ] ||
	fail 'Diagnostics accepted the stopped upstream.'
port=$(cat "$fixture/probe-port")
[ -z "$(ss -H -ltn "sport = :$port")" ] || fail 'The failed diagnostic listener was left open.'
[ -s "$runtime/ready" ]
kill -0 "$client_pid" 2>/dev/null || fail 'Diagnostics stopped the main Xray client.'
for proxy in http://127.0.0.1:17881 socks5h://127.0.0.1:17880; do
	if probe "$proxy" 2> "$fixture/curl.log"; then
		fail "Traffic through $proxy bypassed the stopped upstream."
	fi
done
kill -0 "$client_pid" 2>/dev/null || fail 'The ExConnect Xray client stopped unexpectedly.'

printf '%s\n' 'HTTP and SOCKS traffic passed through the configured Xray upstream.'
