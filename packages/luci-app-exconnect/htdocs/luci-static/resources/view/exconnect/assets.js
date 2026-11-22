'use strict';
'require form';
'require ui';
'require view';
'require exconnect.client as client';

return view.extend({
	render: function () {
		const map = new form.Map('exconnect', _('Rule data'),
			_('Configure HTTPS sources for Xray-compatible .dat files, including RunetFreedom lists.'));
		const assets = map.section(form.GridSection, 'asset', _('Rule data sources'));
		assets.anonymous = true;
		assets.addremove = true;

		const filename = assets.option(form.Value, 'name', _('Filename'));
		filename.placeholder = 'geosite-custom.dat';
		filename.value('geoip-runetfreedom.dat');
		filename.value('geosite-runetfreedom.dat');
		filename.rmempty = false;
		filename.validate = function (sectionId, value) {
			return /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,96}\.dat$/.test(value) ||
				_('Enter a .dat filename using letters, numbers, dots, hyphens or underscores.');
		};

		const url = assets.option(form.Value, 'url', _('HTTPS URL'));
		url.modalonly = true;
		url.rmempty = false;
		url.validate = client.validateHttps;
		url.value('https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat', _('RunetFreedom IP addresses'));
		url.value('https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat', _('RunetFreedom domains'));

		return map.render().then(function (node) {
			return E([
				node,
				E('div', { 'class': 'cbi-section' }, [
					E('p', [_('Save and apply the sources before downloading. Then reference a file and its tag in Routing, for example ext:geosite-runetfreedom.dat:ru-blocked.')]),
					E('button', {
						'type': 'button',
						'class': 'cbi-button cbi-button-action',
						'disabled': !L.hasViewPermission() ? '' : null,
						'click': ui.createHandlerFn(this, function () {
							return client.perform(client.updateAssets,
								_('Rule data was updated. Apply the configuration from Overview to load it.'));
						})
					}, [_('Download rule data')])
				])
			]);
		});
	}
});
