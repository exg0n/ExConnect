'use strict';

import { readfile } from 'fs';
import { cursor } from 'uci';

const config = 'exconnect';

function prepare(body) {
	assert(length(body) <= 1048576, 'Subscription is too large');
	if (substr(body, 0, 3) == chr(239) + chr(187) + chr(191))
		body = substr(body, 3);
	body = trim(body);
	if (!match(body, /:\/\//)) {
		let encoded = replace(replace(replace(body, /[\r\n\t ]/g, ''), /-/g, '+'), /_/g, '/');
		assert(match(encoded, /^[A-Za-z0-9+/]+=*$/), 'Expected share links or Base64');
		while (length(encoded) % 4)
			encoded += '=';
		body = b64dec(encoded);
		assert(type(body) == 'string', 'Invalid Base64 subscription');
	}

	let seen = {};
	let links = [];
	for (let line in split(body, '\n')) {
		line = trim(line);
		if (!match(line, /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^[:cntrl:]]+$/) || seen[line])
			continue;
		assert(length(line) <= 8192 && length(links) < 256, 'Subscription has too many or oversized links');
		seen[line] = true;
		push(links, line);
	}
	assert(length(links), 'No share links found');
	print(join('\n', links) + '\n');
}

function identity(uri) {
	return replace(uri, /#.*$/, '');
}

function nameOf(uri, label, number) {
	let suffix = match(uri, /#(.+)$/);
	if (!suffix)
		return label + ' ' + number;
	let name = replace(suffix[1], /%[0-9a-fA-F]{2}/g, (part) => chr(int(substr(part, 1), 16)));
	name = trim(replace(name, /[[:cntrl:]]/g, ''));
	return length(name) && length(name) <= 128 ? name : label + ' ' + number;
}

function subscriptionUrl(uci, section) {
	assert(uci.get(config, section) == 'subscription', 'Subscription does not exist');
	let url = uci.get(config, section, 'url');
	assert(type(url) == 'string' && !match(url, /[[:space:][:cntrl:]]/), 'Invalid subscription URL');
	return url;
}

function save(uci, section, expectedUrl, candidates, accepted) {
	let links = split(trim(accepted), '\n');
	assert(length(accepted) && length(links) <= 256, 'No supported profiles were accepted');
	assert(subscriptionUrl(uci, section) == expectedUrl, 'Subscription changed during refresh');
	let selection = uci.get(config, 'main', 'profile');
	let label = uci.get(config, section, 'name') || 'Subscription';
	let owned = [];
	let byLink = {};
	uci.foreach(config, 'profile', (profile) => {
		if (profile.subscription != section)
			return;
		let id = profile['.name'];
		let key = identity(profile.uri || '');
		push(owned, id);
		if (!byLink[key] || id == selection)
			byLink[key] = id;
	});

	let kept = {};
	let seen = {};
	let count = 0;
	for (let uri in links) {
		let key = identity(uri);
		if (seen[key])
			continue;
		seen[key] = true;
		let id = byLink[key] || uci.add(config, 'profile');
		assert(id, 'Could not create subscription profile');
		assert(uci.set(config, id, 'subscription', section) &&
			uci.set(config, id, 'name', nameOf(uri, label, count + 1)) &&
			uci.set(config, id, 'uri', uri), 'Could not save subscription profile');
		if (uci.get(config, id, 'stale') != null)
			assert(uci.delete(config, id, 'stale'), 'Could not update subscription profile');
		kept[id] = true;
		count++;
	}

	for (let id in owned) {
		if (kept[id])
			continue;
		if (id == selection) {
			assert(uci.set(config, id, 'stale', '1'), 'Could not keep the selected profile');
			continue;
		}
		assert(uci.delete(config, id), 'Could not remove the obsolete subscription profile');
	}
	assert(uci.commit(config), 'Could not commit subscription changes');
	return { ok: true, count, ignored: length(split(trim(candidates), '\n')) - count };
}

if (ARGV[0] == 'prepare') {
	prepare(readfile(ARGV[1]) || '');
} else if (ARGV[0] == 'url') {
	print(subscriptionUrl(cursor('/etc/config', ARGV[2], ''), ARGV[1]));
} else {
	let dir = ARGV[2];
	try {
		let result = save(cursor('/etc/config', dir, ''), ARGV[1],
			readfile(dir + '/url'), readfile(dir + '/links'), readfile(dir + '/accepted'));
		print(sprintf('%J\n', result));
	} catch (error) {
		print(sprintf('%J\n', { ok: false, error: error.message || 'Could not refresh subscription' }));
	}
}
