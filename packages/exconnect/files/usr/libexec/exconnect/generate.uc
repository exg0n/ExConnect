'use strict';

import { cursor } from 'uci';
import { fdopen } from 'fs';

const actions = [ 'proxy', 'direct', 'block' ];
const packageName = 'exconnect';
const transparentMark = '0x01000000';

function decode(value) {
	return replace(value, /%[0-9a-fA-F]{2}/g, (part) => chr(int(substr(part, 1), 16)));
}

function decodeBase64(value) {
	value = replace(replace(value, /-/g, '+'), /_/g, '/');
	while (length(value) % 4)
		value += '=';
	return b64dec(value);
}

function list(value) {
	if (type(value) == 'array')
		return value;
	return value != null && value != '' ? [ value ] : [];
}

function enabled(value) {
	return value == '1' || value == 'true';
}

function port(value) {
	assert(match('' + value, /^[0-9]+$/) && int(value) > 0 && int(value) <= 65535,
		'Expected a port between 1 and 65535');
	return int(value);
}

function destination(address, value) {
	assert(type(address) == 'string' && match(address, /^[-a-zA-Z0-9_.:]+$/), 'Invalid profile server address');
	return { address, port: port(value) };
}

function parseLink(uri, defaultPort) {
	let parts = match(uri, /^([a-zA-Z0-9]+):\/\/([^#?]+)([?]([^#]*))?(#.*)?$/);
	assert(parts, 'Invalid profile link');
	let query = {};
	for (let item in split(parts[4] || '', '&')) {
		let pair = match(item, /^([^=]+)=(.*)$/);
		if (pair)
			query[decode(pair[1])] = decode(pair[2]);
	}

	let authority = replace(parts[2], /\/$/, '');
	let userinfo = match(authority, /^(.*)@([^@]+)$/);
	let host = userinfo ? userinfo[2] : authority;
	let endpoint = match(host, /^\[([-a-fA-F0-9:.]+)\](:([0-9,-]+))?$/)
		|| match(host, /^([-a-zA-Z0-9_.]+)(:([0-9,-]+))?$/);
	assert(endpoint, 'Invalid profile endpoint');
	let scheme = lc(parts[1]);
	let ports = endpoint[3];
	let hopping = ports && match(ports, /[,-]/);
	if (hopping) {
		assert(scheme == 'hysteria2' || scheme == 'hy2', 'Multiple ports require Hysteria2');
		for (let range in split(ports, ',')) {
			let boundaries = match(range, /^([0-9]+)(-([0-9]+))?$/);
			assert(boundaries, 'Invalid Hysteria2 port range');
			assert(port(boundaries[1]) <= port(boundaries[3] || boundaries[1]), 'Invalid Hysteria2 port range');
		}
	}
	return { scheme, auth: userinfo ? userinfo[1] : '', query,
		ports: hopping ? ports : null,
		server: destination(endpoint[1], ports && split(ports, /[,-]/)[0] || defaultPort) };
}

function streamSettings(transport, security, query, serverName) {
	transport = transport || 'tcp';
	security = security || 'none';
	assert(index([ 'tcp', 'raw', 'ws', 'grpc', 'httpupgrade', 'xhttp', 'kcp', 'hysteria' ], transport) >= 0,
		'Unsupported transport type');
	assert(index([ 'none', 'tls', 'reality' ], security) >= 0, 'Unsupported transport security');

	let stream = { network: transport, security };
	if (transport == 'ws')
		stream.wsSettings = { path: query.path || '/', host: query.host || '' };
	if (transport == 'grpc')
		stream.grpcSettings = { serviceName: query.serviceName || query.path || '',
			multiMode: query.mode == 'multi', authority: query.authority || '' };
	if (transport == 'httpupgrade')
		stream.httpupgradeSettings = { path: query.path || '/', host: query.host || '' };
	if (transport == 'xhttp') {
		stream.xhttpSettings = { path: query.path || '/', host: query.host || '', mode: query.mode || 'auto' };
		if (query.extra)
			stream.xhttpSettings.extra = json(query.extra);
	}
	if (transport == 'kcp')
		stream.kcpSettings = { seed: query.seed || '' };
	if ((transport == 'tcp' || transport == 'raw') && query.headerType == 'http') {
		stream.tcpSettings = { header: { type: 'http', request: {
			path: split(query.path || '/', ','), headers: { Host: split(query.host || serverName, ',') }
		} } };
	}
	if (security == 'tls') {
		let pin = query.pinSHA256 && replace(query.pinSHA256, /:/g, '');
		assert(!pin || match(pin, /^[a-fA-F0-9]{64}$/), 'Expected a 64-digit SHA-256 certificate pin');
		assert(pin || !enabled(query.insecure || query.allowInsecure),
			'Xray requires a trusted certificate or a SHA-256 certificate pin (pinSHA256)');
		stream.tlsSettings = { serverName: query.sni || serverName, useSystemCA: true };
		if (query.alpn)
			stream.tlsSettings.alpn = split(query.alpn, ',');
		if (query.fp)
			stream.tlsSettings.fingerprint = query.fp;
		if (pin)
			stream.tlsSettings.pinnedPeerCertSha256 = pin;
		if (query.ech)
			stream.tlsSettings.echConfigList = query.ech;
	}
	if (security == 'reality') {
		assert(query.pbk, 'REALITY requires a public key');
		stream.realitySettings = { serverName: query.sni || serverName,
			fingerprint: query.fp || 'chrome', password: query.pbk, shortId: query.sid || '',
			spiderX: query.spx || '/' };
	}
	return stream;
}

function vmess(uri) {
	let payload = decodeBase64(split(substr(uri, 8), '#')[0]);
	assert(payload, 'Invalid VMess link encoding');
	let data = json(payload);
	assert(type(data) == 'object' && data.id, 'Invalid VMess profile');
	let server = destination(data.add, data.port);
	let user = { id: data.id, alterId: int(data.aid || 0), security: data.scy || 'auto' };
	let query = { host: data.host, path: data.path, sni: data.sni, fp: data.fp,
		alpn: data.alpn, headerType: data.type, mode: data.type };
	return { tag: 'proxy', protocol: 'vmess',
		settings: { vnext: [ { ...server, users: [ user ] } ] },
		streamSettings: streamSettings(data.net, data.tls, query, server.address) };
}

function shadowsocks(uri) {
	if (index(split(uri, '#')[0], '@') < 0 && index(split(uri, '#')[0], '?') < 0) {
		let legacy = decodeBase64(split(substr(uri, 5), '#')[0]);
		assert(legacy, 'Invalid Shadowsocks link encoding');
		uri = 'ss://' + legacy;
	}
	let link = parseLink(uri, 443);
	assert(!link.query.plugin, 'Shadowsocks SIP003 plugins are unsupported');
	let auth = decode(link.auth);
	if (index(auth, ':') < 0)
		auth = decodeBase64(auth);
	let credentials = auth && match(auth, /^([^:]+):(.+)$/);
	assert(credentials, 'Shadowsocks requires a method and password');
	return { tag: 'proxy', protocol: 'shadowsocks',
		settings: { servers: [ { ...link.server, method: credentials[1], password: credentials[2] } ] } };
}

function outbound(uri) {
	assert(type(uri) == 'string' && length(uri) <= 16384 && !match(uri, /[[:space:][:cntrl:]]/),
		'Expected one complete profile link');
	if (substr(uri, 0, 8) == 'vmess://')
		return vmess(uri);
	if (substr(uri, 0, 5) == 'ss://')
		return shadowsocks(uri);

	let link = parseLink(uri, substr(uri, 0, 7) == 'http://' ? 80 :
		(match(uri, /^socks5?:\/\//) ? 1080 : 443));
	let query = link.query;
	let auth = decode(link.auth);
	let protocol = link.scheme;
	let server = link.server;

	if (protocol == 'hysteria2' || protocol == 'hy2') {
		assert(auth, 'Hysteria2 requires a password');
		let stream = streamSettings('hysteria', 'tls', query, server.address);
		stream.hysteriaSettings = { version: 2, auth };
		let mask = {};
		if (link.ports)
			mask.quicParams = { udpHop: { ports: link.ports, interval: '30' } };
		if (query.obfs) {
			assert(query.obfs == 'salamander' && query['obfs-password'], 'Unsupported Hysteria2 obfuscation');
			mask.udp = [ { type: 'salamander', settings: { password: query['obfs-password'] } } ];
		}
		if (length(keys(mask)))
			stream.finalmask = mask;
		return { tag: 'proxy', protocol: 'hysteria', settings: { ...server, version: 2 }, streamSettings: stream };
	}

	if (protocol == 'vless' || protocol == 'trojan') {
		assert(auth, 'Profile requires credentials');
		let stream = streamSettings(query.type, query.security || (protocol == 'trojan' ? 'tls' : 'none'),
			query, server.address);
		if (protocol == 'vless') {
			let user = { id: auth, encryption: query.encryption || 'none', flow: query.flow || '' };
			return { tag: 'proxy', protocol, streamSettings: stream,
				settings: { vnext: [ { ...server, users: [ user ] } ] } };
		}
		return { tag: 'proxy', protocol, streamSettings: stream,
			settings: { servers: [ { ...server, password: auth } ] } };
	}

	assert(index([ 'socks', 'socks5', 'http', 'https' ], protocol) >= 0, 'Unsupported profile protocol');
	if (auth) {
		let credentials = match(link.auth, /^([^:]+):(.+)$/);
		assert(credentials, 'Expected username and password');
		server.users = [ { user: decode(credentials[1]), pass: decode(credentials[2]) } ];
	}
	let secure = protocol == 'https';
	return { tag: 'proxy', protocol: (protocol == 'socks5' ? 'socks' : (secure ? 'http' : protocol)),
		settings: { servers: [ server ] },
		streamSettings: streamSettings('tcp', secure ? 'tls' : 'none', query, server.address) };
}

function assetName(value) {
	return value && match(value, /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,96}\.dat$/);
}

function validateMatchers(values) {
	for (let value in values) {
		if (match(value, /^!?ext:/)) {
			let parts = match(value, /^!?ext:([^:]+):[^:[:space:]]+$/);
			assert(parts && assetName(parts[1]), 'Invalid external DAT rule');
		}
	}
	return values;
}

function routingText(uci, main, rules, defaultAction) {
	let assets = {};
	uci.foreach(packageName, 'asset', (asset) => { assets[asset.name] = true; });
	let declaredDefault = false;
	let lines = split(main.routing_text || '', '\n');
	for (let number = 0; number < length(lines); number++) {
		let line = trim(lines[number]);
		if (!line || match(line, /^#/))
			continue;
		let prefix = sprintf('RoutingA line %d: ', number + 1);
		let fallback = match(line, /^default[[:space:]]*:[[:space:]]*(direct|proxy|block)[[:space:]]*(#.*)?$/);
		if (fallback) {
			assert(!declaredDefault, prefix + 'duplicate default');
			declaredDefault = true;
			defaultAction = fallback[1];
			continue;
		}
		let rule = match(line, /^(domain|geoip|ip|protocol)[[:space:]]*\((.+)\)[[:space:]]*->[[:space:]]*(direct|proxy|block)[[:space:]]*(#.*)?$/);
		assert(rule, prefix + 'expected domain, geoip, ip or protocol rule');
		let selector = rule[1];
		let values = map(split(rule[2], ','), (entry) => trim(entry));
		let key = selector == 'geoip' ? 'ip' : selector;
		for (let n = 0; n < length(values); n++) {
			let value = values[n];
			assert(value, prefix + 'empty selector');
			if (selector == 'protocol')
				assert(index([ 'http', 'tls', 'quic', 'bittorrent' ], value) >= 0, prefix + 'unsupported protocol');
			if (selector == 'geoip' && index(value, ':') < 0)
				value = 'geoip:' + value;
			if (selector == 'domain' && substr(value, 0, 9) == 'contains:')
				value = 'keyword:' + trim(substr(value, 9));
			let category = match(value, /^(geosite|geoip):(.+)$/);
			assert(!category || category[1] != 'geoip' || substr(category[2], 0, 1) != '!',
				prefix + 'inverted GeoIP selectors are not supported');
			if (category && assets[category[1] + '-runetfreedom.dat'])
				value = 'ext:' + category[1] + '-runetfreedom.dat:' + category[2];
			values[n] = value;
		}
		let compiled = { type: 'field', outboundTag: rule[3] };
		compiled[key] = validateMatchers(values);
		push(rules, compiled);
	}
	return defaultAction;
}

function generate(uci, main) {
	let defaultAction = main.default_action || 'proxy';
	assert(index(actions, defaultAction) >= 0, 'Invalid default routing action');
	let socks = port(main.socks_port || 1080);
	let http = port(main.http_port || 8080);
	assert(socks != http, 'Local ports must be different');
	let sniffing = { enabled: true, destOverride: [ 'http', 'tls', 'quic' ], routeOnly: true };
	let inbounds = [
		{ tag: 'socks-in', protocol: 'socks', listen: '127.0.0.1', port: socks, settings: { udp: true }, sniffing },
		{ tag: 'http-in', protocol: 'http', listen: '127.0.0.1', port: http, sniffing }
	];
	let mode = main.mode || 'local';
	assert(mode == 'local' || mode == 'transparent', 'Invalid proxy mode');
	if (mode == 'transparent') {
		let tproxy = port(main.tproxy_port || 12345);
		assert(tproxy != socks && tproxy != http, 'Transparent port overlaps a local port');
		let settings = { network: 'tcp,udp', followRedirect: true };
		push(inbounds, { tag: 'lan-ipv4-in', protocol: 'dokodemo-door', listen: '127.0.0.1',
			port: tproxy, settings, streamSettings: { sockopt: { tproxy: 'tproxy' } }, sniffing });
		// Enable IPV6_TRANSPARENT for the dedicated IPv6 listener.
		let ipv6Socket = { tproxy: 'tproxy',
			customSockopt: [ { system: 'linux', type: 'int', level: '41', opt: '75', value: '1' } ] };
		push(inbounds, { tag: 'lan-ipv6-in', protocol: 'dokodemo-door', listen: '::1',
			port: tproxy, settings, streamSettings: { sockopt: ipv6Socket }, sniffing });
	}

	let rules = [];
	if (main.routing_mode == 'text')
		defaultAction = routingText(uci, main, rules, defaultAction);
	else uci.foreach(packageName, 'rule', (rule) => {
		if (rule.enabled != null && !enabled(rule.enabled))
			return;
		assert(index(actions, rule.action) >= 0, 'Invalid routing action');
		let domains = validateMatchers(list(rule.domains));
		let ips = validateMatchers(list(rule.ips));
		assert(length(domains) || length(ips), 'An enabled routing rule needs a matcher');
		if (length(domains))
			push(rules, { type: 'field', domain: domains, outboundTag: rule.action });
		if (length(ips))
			push(rules, { type: 'field', ip: ips, outboundTag: rule.action });
	});
	push(rules, { type: 'field', network: 'tcp,udp', outboundTag: defaultAction });

	let outbounds = [
		{ tag: 'direct', protocol: 'freedom' },
		{ tag: 'block', protocol: 'blackhole' }
	];
	if (main.profile) {
		let selected = uci.get_all(packageName, main.profile);
		assert(selected && selected['.type'] == 'profile', 'Selected profile does not exist');
		push(outbounds, outbound(selected.uri));
	} else {
		for (let rule in rules)
			assert(rule.outboundTag != 'proxy', 'Select a profile for proxy routing');
	}

	let loglevel = main.log_level || 'warning';
	assert(index([ 'none', 'error', 'warning', 'info', 'debug' ], loglevel) >= 0, 'Invalid log level');
	printf('%J\n', { log: { loglevel }, inbounds, outbounds,
		routing: { domainStrategy: 'IPOnDemand', rules } });
}

function probeConfig(uci, id, localPort) {
	let selected = id && uci.get_all(packageName, id);
	assert(selected && selected['.type'] == 'profile', 'Select a saved connection profile');
	printf('%J\n', {
		log: { loglevel: 'warning' },
		inbounds: [ { protocol: 'socks', listen: '127.0.0.1', port: port(localPort) } ],
		outbounds: [ outbound(selected.uri) ]
	});
}

function nftables(main) {
	if (main.mode != 'transparent')
		return;
	let interfaces = list(main.interfaces);
	if (!length(interfaces))
		interfaces = [ 'br-lan' ];
	for (let name in interfaces)
		assert(match(name, /^[-a-zA-Z0-9_.]{1,15}$/), 'Invalid transparent proxy interface');

	printf('table inet exconnect {\n');
	printf(' chain prerouting {\n');
	printf('  type filter hook prerouting priority mangle - 5; policy accept;\n');
	printf('  iifname != { %s } return\n', join(', ', map(interfaces, (name) => sprintf('"%s"', name))));
	printf('  fib daddr type local return\n');
	printf('  ip daddr { 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return\n');
	printf('  ip6 daddr { ::/128, ::1/128, fc00::/7, fe80::/10, ff00::/8 } return\n');
	let tproxy = port(main.tproxy_port || 12345);
	printf('  meta l4proto { tcp, udp } tproxy ip to 127.0.0.1:%d meta mark set meta mark | %s accept\n',
		tproxy, transparentMark);
	printf('  meta l4proto { tcp, udp } tproxy ip6 to [::1]:%d meta mark set meta mark | %s accept\n',
		tproxy, transparentMark);
	printf(' }\n}\n');
}

function assets(uci) {
	let seen = {};
	uci.foreach(packageName, 'asset', (asset) => {
		assert(assetName(asset.name) && !seen[asset.name], 'DAT filenames must be unique and end in .dat');
		seen[asset.name] = true;
		if (!asset.url)
			return;
		assert(match(asset.url, /^https:\/\/[^[:space:][:cntrl:]]+$/), 'DAT source must use HTTPS');
		printf('%s %s\n', asset.name, asset.url);
	});
}

function assetSnapshot(uci) {
	let sources = [];
	uci.foreach(packageName, 'asset', (asset) => {
		push(sources, { section: asset['.name'], name: asset.name, url: asset.url || '' });
	});
	printf('%J\n', sources);
}

function checkLinks() {
	let input = fdopen(0, 'r');
	let line;
	while ((line = input.read('line'))) {
		line = trim(line);
		if (!line)
			continue;
		try {
			outbound(line);
			printf('%s\n', line);
		} catch (error) {
			// Subscription responses may contain unsupported or malformed entries.
		}
	}
}

try {
	let command = ARGV[0] || 'generate';
	if (command == 'check-uri') {
		checkLinks();
		exit(0);
	}
	let configDir = command == 'probe' ? ARGV[3] : ARGV[1];
	let uci = configDir ? cursor(configDir, configDir + '/delta', '') : cursor('/etc/config', '/var/run/exconnect', '');
	let main = uci.get_all(packageName, 'main');
	assert(main && main['.type'] == 'service', 'Missing ExConnect service settings');
	switch (command) {
	case 'generate':
		generate(uci, main);
		break;
	case 'probe':
		probeConfig(uci, ARGV[1], ARGV[2]);
		break;
	case 'nftables':
		nftables(main);
		break;
	case 'assets':
		assets(uci);
		break;
	case 'asset_snapshot':
		assetSnapshot(uci);
		break;
	default:
		assert(false, 'Unsupported generator command');
	}
} catch (error) {
	warn(error.message || 'Invalid ExConnect configuration', '\n');
	exit(1);
}
