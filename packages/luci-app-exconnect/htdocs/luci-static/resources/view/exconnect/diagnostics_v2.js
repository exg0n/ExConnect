'use strict';
'require uci';
'require ui';
'require view';
'require rpc';

// Keep these calls with this view so an app upgrade can load diagnostics even
// while the browser retains an earlier shared client module.
const callLogs = rpc.declare({ object: 'exconnect', method: 'logs', reject: true });
const callProbe = rpc.declare({
	object: 'exconnect', method: 'probe', params: [ 'section', 'kind' ], reject: true
});

function showLog(node, result) {
	node.textContent = !result || result.ok !== true
		? _('Could not read the ExConnect log.')
		: result.log || _('No ExConnect log entries.');
}

return view.extend({
	load: function () {
		return Promise.all([
			uci.load('exconnect'),
			L.resolveDefault(callLogs(), null)
		]);
	},

	render: function (data) {
		const profiles = uci.sections('exconnect', 'profile');
		const readOnly = !L.hasViewPermission();
		const profile = E('select', { 'class': 'cbi-input-select', 'id': 'exconnect-diagnostic-profile' },
			profiles.map(function (section) {
				return E('option', { 'value': section['.name'] }, [section.name || section['.name']]);
			}));
		const current = uci.get('exconnect', 'main', 'profile');
		if (profiles.some(function (section) { return section['.name'] === current; }))
			profile.value = current;

		const latency = E('p', { 'aria-live': 'polite' });
		const speed = E('p', { 'aria-live': 'polite' });
		const log = E('pre', {
			'style': 'max-height: 24em; overflow: auto; white-space: pre-wrap; overflow-wrap: anywhere;',
			'tabindex': '0',
			'aria-label': _('ExConnect log')
		});
		const controls = [profile];
		const canProbe = !readOnly && profiles.length > 0;
		profile.disabled = !canProbe;
		profile.addEventListener('change', function () {
			latency.textContent = '';
			speed.textContent = '';
		});

		function probeButton(label, kind, resultNode, formatResult) {
			const button = E('button', {
				'type': 'button',
				'class': 'cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, function () {
					controls.forEach(function (control) { control.disabled = true; });
					resultNode.textContent = _('Testing connection…');
					return callProbe(profile.value, kind).then(function (result) {
						if (!result || result.ok !== true)
							throw new Error(result && result.error || _('The connection test failed.'));
						resultNode.textContent = formatResult(result);
					}).catch(function (error) {
						resultNode.textContent = String(error.message || error);
					}).finally(function () {
						controls.forEach(function (control) { control.disabled = !canProbe; });
					});
				})
			}, [label]);
			button.disabled = !canProbe;
			controls.push(button);
			return button;
		}

		const latencyButton = probeButton(_('Check ping'), 'latency', latency, function (result) {
			return _('HTTPS latency: %s ms').format(Math.round(result.latency_ms));
		});
		const speedButton = probeButton(_('Test download speed'), 'speed', speed, function (result) {
			return _('Download: %s Mbit/s (%s bytes)').format(Number(result.speed_mbps).toFixed(2), result.bytes);
		});

		showLog(log, data[1]);
		return E([
			E('h2', [_('Diagnostics')]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', [_('Connection test')]),
				E('p', [_('Tests open a separate connection from the router through the selected saved profile before or while the service runs.')]),
				E('p', [_('Ping is an HTTPS response time. The download test transfers up to 2 MB.')]),
				profiles.length ? E('div', [
					E('label', { 'for': 'exconnect-diagnostic-profile' }, [_('Connection profile')]), ' ',
					profile, ' ', latencyButton, ' ', speedButton, latency, speed
				]) : E('p', [_('Save a connection profile in Profiles and subscriptions first.')])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', [_('ExConnect log')]),
				log,
				E('button', {
					'type': 'button',
					'class': 'cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, function () {
						return L.resolveDefault(callLogs(), null).then(function (result) {
							showLog(log, result);
						});
					})
				}, [_('Refresh log')])
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
