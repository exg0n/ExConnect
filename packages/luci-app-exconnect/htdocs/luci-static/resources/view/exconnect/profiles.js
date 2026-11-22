'use strict';
'require form';
'require uci';
'require view';
'require exconnect.subscriptions as subscriptionEditor';

function source(profile) {
	return profile && profile.subscription && uci.get('exconnect', profile.subscription);
}

return view.extend({
	load: function () {
		return uci.load('exconnect');
	},

	render: function () {
		const map = new form.Map('exconnect', _('Profiles and subscriptions'),
			_('Add connection share links here and select the active profile in Settings.'));
		const profiles = map.section(form.GridSection, 'profile', _('Connection profiles'));
		profiles.anonymous = true;
		profiles.addremove = true;
		profiles.filter = function (sectionId) {
			return !source(uci.get('exconnect', sectionId));
		};

		const name = profiles.option(form.Value, 'name', _('Profile name'));
		name.rmempty = false;

		const uri = profiles.option(form.Value, 'uri', _('Share link'),
			_('Supported schemes include Hysteria2, VLESS, VMess, Trojan, Shadowsocks, SOCKS and HTTP. Hysteria2 requires a trusted certificate or a supported certificate pin.'));
		uri.modalonly = true;
		uri.password = true;
		uri.rmempty = false;
		uri.validate = function (sectionId, value) {
			return /^(hysteria2|hy2|vless|vmess|trojan|ss|socks|socks5|http|https):\/\/\S+$/i.test(value) ||
				_('Enter a complete share link using a supported protocol.');
		};
		subscriptionEditor.addTo(map);

		return map.render().then(function (node) {
			const rows = [];
			uci.sections('exconnect', 'profile', function (profile) {
				const subscription = source(profile);
				if (!subscription)
					return;

				rows.push(E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left' }, [profile.name || profile['.name']]),
					E('div', { 'class': 'td left' }, [subscription.name || subscription['.name']]),
					E('div', { 'class': 'td left' }, [
						profile.stale === '1' ? _('Removed by provider') : _('Available')
					])
				]));
			});

			if (!rows.length)
				return node;

			return E([
				node,
				E('div', { 'class': 'cbi-section' }, [
					E('h3', [_('Subscription profiles')]),
					E('div', { 'class': 'table' }, [
						E('div', { 'class': 'tr table-titles' }, [
							E('div', { 'class': 'th left' }, [_('Profile name')]),
							E('div', { 'class': 'th left' }, [_('Subscription')]),
							E('div', { 'class': 'th left' }, [_('Status')])
						])
					].concat(rows))
				])
			]);
		});
	}
});
