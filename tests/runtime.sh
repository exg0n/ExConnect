#!/bin/sh
set -eu

generator=${1:-/usr/libexec/exconnect/generate.uc}
subscriptions=${2:-/usr/libexec/exconnect/subscriptions.uc}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 1' HUP INT TERM
mkdir "$fixture/delta"

expect_value() {
	actual=$(jsonfilter -i "$fixture/config.json" -e "$1")
	if [ "$actual" != "$2" ]; then
		printf 'Assertion failed for %s. Expected %s, got %s\n' "$1" "$2" "$actual" >&2
		exit 1
	fi
}

expect_invalid() {
	if ucode "$generator" generate "$fixture" > "$fixture/config.json" 2> "$fixture/error"; then
		printf 'Invalid fixture generated a configuration (%s)\n' "$1" >&2
		exit 1
	fi
	grep -Eiq "$1" "$fixture/error" || { cat "$fixture/error" >&2; exit 1; }
}

expect_profile() {
	set_fixture "$1"
	ucode "$generator" generate "$fixture" > "$fixture/config.json"
	expect_value '@.outbounds[@.tag="proxy"].protocol' "$2"
	XRAY_LOCATION_ASSET="$fixture" xray run -test -config "$fixture/config.json"
}

fixture_uci() {
	uci -c "$fixture" -P "$fixture/delta" "$@"
}

set_fixture() {
	cat > "$fixture/exconnect" <<EOF
config service 'main'
	option enabled '1'
	option mode 'transparent'
	option profile 'upstream'
	option socks_port '17080'
	option http_port '17081'
	option tproxy_port '17082'
	option default_action 'proxy'
	list interfaces 'br-lan'
config profile 'upstream'
	option name 'Fixture'
	option uri '$1'
config rule 'external_site'
	option action 'direct'
	list domains 'ext:qa-geosite.dat:fixture'
config rule 'external_ip'
	option action 'block'
	list ips 'ext:qa-geoip.dat:fixture'
config asset 'test_site'
	option name 'qa-geosite.dat'
	option url 'https://example.test/geosite.dat'
EOF
}

# Minimal V2Ray protobuf lists with the tag FIXTURE, a full domain and a CIDR.
printf '\012\033\012\007FIXTURE\022\020\010\003\022\014example.test' > "$fixture/qa-geosite.dat"
printf '\012\023\012\007FIXTURE\022\010\012\004\300\000\002\000\020\030' > "$fixture/qa-geoip.dat"

for scheme in hysteria2 hy2; do
	set_fixture "$scheme://qa%3Apass@example.test:8443/?sni=proxy.example.test&obfs=salamander&obfs-password=maskpass#Fixture"
	ucode "$generator" generate "$fixture" > "$fixture/config.json"
	expect_value '@.outbounds[@.tag="proxy"].protocol' 'hysteria'
	expect_value '@.outbounds[@.tag="proxy"].settings.version' '2'
	expect_value '@.outbounds[@.tag="proxy"].settings.port' '8443'
	expect_value '@.outbounds[@.tag="proxy"].streamSettings.hysteriaSettings.auth' 'qa:pass'
	expect_value '@.outbounds[@.tag="proxy"].streamSettings.tlsSettings.serverName' 'proxy.example.test'
	expect_value '@.outbounds[@.tag="proxy"].streamSettings.finalmask.udp[0].type' 'salamander'
	expect_value '@.outbounds[@.tag="proxy"].streamSettings.finalmask.udp[0].settings.password' 'maskpass'
	expect_value '@.routing.rules[0].domain[0]' 'ext:qa-geosite.dat:fixture'
	expect_value '@.routing.rules[1].ip[0]' 'ext:qa-geoip.dat:fixture'
	expect_value '@.inbounds[@.protocol="socks"].listen' '127.0.0.1'
	XRAY_LOCATION_ASSET="$fixture" xray run -test -config "$fixture/config.json"
done

ucode "$generator" nftables "$fixture" > "$fixture/exconnect.nft"
grep -Fq 'iifname != { "br-lan" } return' "$fixture/exconnect.nft"
grep -Fq 'tproxy ip to 127.0.0.1:17082' "$fixture/exconnect.nft"
grep -Fq 'tproxy ip6 to [::1]:17082' "$fixture/exconnect.nft"
ucode "$generator" assets "$fixture" | grep -q '^qa-geosite.dat https://example.test/geosite.dat$'

pin=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
expect_profile "hy2://qa@example.test:8443,8444-8446/?insecure=1&pinSHA256=$pin" hysteria
expect_value '@.outbounds[@.tag="proxy"].streamSettings.tlsSettings.pinnedPeerCertSha256' "$pin"
expect_value '@.outbounds[@.tag="proxy"].streamSettings.finalmask.quicParams.udpHop.ports' '8443,8444-8446'

vmess_config='{"add":"example.test","port":443,"id":"8194561b-cea5-423f-8c89-054a41796e2e","aid":0,"net":"ws","path":"/proxy","tls":"tls"}'
encoded=$(printf '%s' "$vmess_config" | base64 | tr -d '\n')
expect_profile "vmess://$encoded" vmess
expect_profile 'vless://8194561b-cea5-423f-8c89-054a41796e2e@example.test:443?type=ws&path=%2Fproxy&security=tls' vless
expect_profile 'trojan://qa@example.test:443' trojan
expect_profile 'ss://aes-128-gcm:qa@example.test:443' shadowsocks
expect_profile 'socks5://qa:pass@example.test:1080' socks
expect_profile 'https://qa:pass@example.test:443' http

set_fixture 'socks5://qa:pass@example.test:1080'
cp "$fixture/qa-geosite.dat" "$fixture/geosite-runetfreedom.dat"
cp "$fixture/qa-geoip.dat" "$fixture/geoip-runetfreedom.dat"
fixture_uci set exconnect.site_data=asset
fixture_uci set exconnect.site_data.name=geosite-runetfreedom.dat
fixture_uci set exconnect.ip_data=asset
fixture_uci set exconnect.ip_data.name=geoip-runetfreedom.dat
fixture_uci set exconnect.main.routing_mode=text
fixture_uci set 'exconnect.main.routing_text=# comment
default: direct # fallback
protocol(bittorrent)->direct
domain(geosite:fixture, domain:text.example, plain.example, contains:legacy) -> proxy
geoip(fixture)->proxy
ip(192.0.2.0/24)->block'
fixture_uci commit exconnect
ucode "$generator" generate "$fixture" > "$fixture/config.json"
expect_value '@.routing.rules[0].protocol[0]' 'bittorrent'
expect_value '@.routing.rules[0].outboundTag' 'direct'
expect_value '@.routing.rules[1].domain[0]' 'ext:geosite-runetfreedom.dat:fixture'
expect_value '@.routing.rules[1].domain[1]' 'domain:text.example'
expect_value '@.routing.rules[1].domain[2]' 'plain.example'
expect_value '@.routing.rules[1].domain[3]' 'keyword:legacy'
expect_value '@.routing.rules[1].outboundTag' 'proxy'
expect_value '@.routing.rules[2].ip[0]' 'ext:geoip-runetfreedom.dat:fixture'
expect_value '@.routing.rules[3].ip[0]' '192.0.2.0/24'
expect_value '@.routing.rules[3].outboundTag' 'block'
expect_value '@.routing.rules[4].outboundTag' 'direct'
XRAY_LOCATION_ASSET="$fixture" xray run -test -config "$fixture/config.json"

fixture_uci set 'exconnect.main.routing_text=domain(domain:text.example)->direct'
fixture_uci commit exconnect
ucode "$generator" generate "$fixture" > "$fixture/config.json"
expect_value '@.routing.rules[1].outboundTag' 'proxy'

fixture_uci set 'exconnect.main.routing_text=default: direct
default: proxy'
fixture_uci commit exconnect
expect_invalid 'RoutingA line 2.*duplicate default'
fixture_uci set 'exconnect.main.routing_text=# comment
protocol(other)->direct'
fixture_uci commit exconnect
expect_invalid 'RoutingA line 2.*unsupported protocol'

# A diagnostic config ignores the saved routing rules and binds only to loopback.
ucode "$generator" probe upstream 17091 "$fixture" > "$fixture/config.json"
expect_value '@.inbounds[0].listen' '127.0.0.1'
expect_value '@.inbounds[0].protocol' 'socks'
expect_value '@.inbounds[0].port' '17091'
expect_value '@.outbounds[0].protocol' 'socks'
expect_value '@.outbounds[0].tag' 'proxy'
! grep -q 'routing\|dokodemo-door\|freedom' "$fixture/config.json"
xray run -test -config "$fixture/config.json"
if ucode "$generator" probe missing 17091 "$fixture" > "$fixture/config.json" 2> "$fixture/error"; then
	printf '%s\n' 'Diagnostic config accepted a missing profile' >&2
	exit 1
fi
grep -qi 'saved connection profile' "$fixture/error"

# Switching back to table mode preserves legacy rules, even with unsound saved RoutingA text.
fixture_uci set exconnect.main.routing_mode=table
fixture_uci commit exconnect
ucode "$generator" generate "$fixture" > "$fixture/config.json"
expect_value '@.routing.rules[0].domain[0]' 'ext:qa-geosite.dat:fixture'
expect_value '@.routing.rules[1].ip[0]' 'ext:qa-geoip.dat:fixture'

set_fixture 'socks5://qa:pass@example.test:1080'
fixture_uci delete exconnect.main.profile
fixture_uci set exconnect.main.routing_mode=text
fixture_uci set 'exconnect.main.routing_text=default: direct
domain(geosite:fixture)->block
geoip(fixture)->direct'
fixture_uci commit exconnect
ucode "$generator" generate "$fixture" > "$fixture/config.json"
expect_value '@.routing.rules[0].domain[0]' 'geosite:fixture'
expect_value '@.routing.rules[1].ip[0]' 'geoip:fixture'
expect_value '@.routing.rules[2].outboundTag' 'direct'
fixture_uci set 'exconnect.main.routing_text=default: direct
domain(domain:text.example)->proxy'
fixture_uci commit exconnect
expect_invalid 'Select a profile for proxy routing'

set_fixture 'hysteria2://qa@example.test:8443/?insecure=1'
expect_invalid 'insecure|pin'
set_fixture 'hy2://qa@example.test:70000'
expect_invalid 'port'
set_fixture 'hy2://example.test:443'
expect_invalid 'password'
set_fixture 'hy2://qa@example.test:443/?obfs=salamander'
expect_invalid 'obfuscat'

valid_link='hy2://qa@example.test:443/#Example'
unsupported_link='unsupported://qa@example.test:443/#Ignored'
printf '\357\273\277%s\r\n%s\r\n%s\r\n' "$valid_link" "$valid_link" "$unsupported_link" > "$fixture/plain"
printf '%s\n' "$valid_link" "$unsupported_link" > "$fixture/expected"
base64 "$fixture/expected" > "$fixture/encoded"
for encoding in plain encoded; do
	ucode "$subscriptions" prepare "$fixture/$encoding" > "$fixture/prepared"
	cmp "$fixture/expected" "$fixture/prepared"
	ucode "$generator" check-uri < "$fixture/prepared" > "$fixture/accepted"
	[ "$(cat "$fixture/accepted")" = "$valid_link" ]
done

printf 'Configuration smoke checks passed.\n'
