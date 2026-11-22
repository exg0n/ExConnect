'use strict';
'require form';
'require uci';
'require view';

return view.extend({
	load: function () {
		return uci.load('exconnect');
	},

	render: function () {
		const map = new form.Map('exconnect', _('Settings'));
		const main = map.section(form.NamedSection, 'main', 'service', _('Service settings'));

		const enabled = main.option(form.Flag, 'enabled', _('Enable service on startup'));
		enabled.default = enabled.disabled;
		enabled.rmempty = false;

		const profile = main.option(form.ListValue, 'profile', _('Connection profile'));
		profile.value('', _('None'));
		uci.sections('exconnect', 'profile', function (section) {
			profile.value(section['.name'], section.name || section['.name']);
		});

		const mode = main.option(form.ListValue, 'mode', _('Proxy mode'));
		mode.value('local', _('Local SOCKS and HTTP proxies'));
		mode.value('transparent', _('Transparent proxy for selected LAN devices'));
		mode.default = 'local';
		mode.rmempty = false;

		const interfaces = main.option(form.DynamicList, 'interfaces', _('LAN ingress devices'),
			_('Enter Linux device names such as br-lan. Transparent mode applies to traffic entering these devices.'));
		interfaces.default = ['br-lan'];
		interfaces.depends('mode', 'transparent');
		interfaces.retain = true;
		interfaces.validate = function (sectionId, value) {
			return /^[A-Za-z0-9_][A-Za-z0-9_.-]{0,14}$/.test(value) || _('Enter a valid Linux device name.');
		};

		const defaultAction = main.option(form.ListValue, 'default_action', _('Unmatched traffic'));
		defaultAction.value('proxy', _('Proxy'));
		defaultAction.value('direct', _('Direct'));
		defaultAction.value('block', _('Block'));
		defaultAction.default = 'proxy';
		defaultAction.rmempty = false;

		const socksPort = main.option(form.Value, 'socks_port', _('SOCKS port'));
		socksPort.datatype = 'and(uinteger,range(1,65535))';
		socksPort.default = '1080';
		socksPort.rmempty = false;

		const httpPort = main.option(form.Value, 'http_port', _('HTTP proxy port'));
		httpPort.datatype = 'and(uinteger,range(1,65535))';
		httpPort.default = '8080';
		httpPort.rmempty = false;

		const tproxyPort = main.option(form.Value, 'tproxy_port', _('Transparent proxy port'));
		tproxyPort.datatype = 'and(uinteger,range(1,65535))';
		tproxyPort.default = '12345';
		tproxyPort.depends('mode', 'transparent');
		tproxyPort.retain = true;

		const logLevel = main.option(form.ListValue, 'log_level', _('Log level'));
		logLevel.value('none', _('Off'));
		logLevel.value('error', _('Errors'));
		logLevel.value('warning', _('Warnings'));
		logLevel.value('info', _('Informational'));
		logLevel.value('debug', _('Debug'));
		logLevel.default = 'warning';
		logLevel.rmempty = false;

		return map.render().then(function (node) {
			return E([
				node,
				E('div', { 'class': 'cbi-section' }, [
					E('p', [_('ExConnect uses the language selected in LuCI.')]),
					E('a', {
						'class': 'cbi-button',
						'href': L.url('admin', 'system', 'system')
					}, [_('Open LuCI language settings')])
				])
			]);
		});
	}
});
