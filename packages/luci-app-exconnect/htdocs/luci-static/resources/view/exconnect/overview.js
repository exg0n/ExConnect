'use strict';
'require dom';
'require poll';
'require ui';
'require uci';
'require view';
'require exconnect.client as client';

function statusLine(label, value) {
	return E('div', { 'class': 'tr' }, [
		E('div', { 'class': 'td left', 'width': '35%' }, [label]),
		E('div', { 'class': 'td left' }, [E('strong', [String(value)])])
	]);
}

function renderStatus(node, status) {
	if (!status || typeof status.running !== 'boolean') {
		dom.content(node, E('p', [_('ExConnect service status is unavailable.')]));
		return;
	}

	const profile = status.profile && uci.get('exconnect', status.profile, 'name');
	const lines = [
		statusLine(_('Service state'), status.running ? _('Running') : _('Stopped')),
		statusLine(_('Enabled on startup'), status.enabled ? _('Yes') : _('No')),
		statusLine(_('Connection profile'), profile || status.profile || _('None'))
	];

	if (status.version)
		lines.push(statusLine(_('Core version'), status.version));
	if (status.last_error)
		lines.push(statusLine(_('Last error'), status.last_error));

	dom.content(node, E('div', { 'class': 'table' }, lines));
}

return view.extend({
	load: function () {
		return Promise.all([
			L.resolveDefault(client.status(), null),
			uci.load('exconnect')
		]);
	},

	render: function (data) {
		const statusNode = E('div', { 'aria-live': 'polite' });
		const readOnly = !L.hasViewPermission();
		const refresh = function () {
			return L.resolveDefault(client.status(), null).then(function (status) {
				renderStatus(statusNode, status);
			});
		};
		const controls = [];

		function button(label, style, request, success) {
			const element = E('button', {
				'type': 'button',
				'class': 'cbi-button ' + style,
				'disabled': readOnly ? '' : null,
				'click': ui.createHandlerFn(this, function () {
					controls.forEach(function (control) { control.disabled = true; });
					return client.perform(request, success).then(refresh).finally(function () {
						controls.forEach(function (control) { control.disabled = readOnly; });
					});
				})
			}, [label]);
			controls.push(element);
			return element;
		}

		renderStatus(statusNode, data[0]);
		poll.add(refresh, 5);

		return E([
			E('h2', [_('ExConnect')]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', [_('Service status')]),
				statusNode,
				E('div', { 'class': 'cbi-page-actions' }, [
					button(_('Validate configuration'), 'cbi-button-neutral', client.validate,
						_('The saved configuration passed validation.')),
					' ',
					button(_('Apply configuration'), 'cbi-button-apply', client.apply,
						_('The saved configuration was applied.')),
					' ',
					button(_('Stop service'), 'cbi-button-reset', client.stop,
						_('The service was stopped.'))
				]),
				E('p', [_('Save and apply changes in each tab before running these actions. Stop service is temporary. To disable startup, use Settings.')])
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
