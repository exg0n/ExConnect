'use strict';
'require baseclass';
'require rpc';
'require ui';

const status = rpc.declare({ object: 'exconnect', method: 'status', reject: true });
const apply = rpc.declare({ object: 'exconnect', method: 'apply', reject: true });
const stop = rpc.declare({ object: 'exconnect', method: 'stop', reject: true });
const validate = rpc.declare({ object: 'exconnect', method: 'validate', reject: true });
const updateAssets = rpc.declare({ object: 'exconnect', method: 'update_assets', reject: true });
const probe = rpc.declare({ object: 'exconnect', method: 'probe', params: [ 'section', 'kind' ], reject: true });
const logs = rpc.declare({ object: 'exconnect', method: 'logs', reject: true });
const refreshSubscription = rpc.declare({
	object: 'exconnect-subscriptions',
	method: 'refresh',
	params: [ 'section' ],
	reject: true
});

return baseclass.extend({
	status: status,
	apply: apply,
	stop: stop,
	validate: validate,
	updateAssets: updateAssets,
	probe: probe,
	logs: logs,
	refreshSubscription: refreshSubscription,

	validateHttps: function (sectionId, value) {
		const message = _('Enter a valid HTTPS URL without credentials.');
		if (!/^https:\/\/[^\s"\\]+$/.test(value))
			return message;

		try {
			const parsed = new URL(value);
			return (parsed.hostname && !parsed.username && !parsed.password) || message;
		} catch (error) {
			return message;
		}
	},

	perform: function (request, success) {
		return request().then(function (result) {
			if (!result || result.ok !== true)
				throw new Error(result && result.error ? result.error : _('The operation failed.'));

			const message = typeof success === 'function' ? success(result) : success;
			ui.addNotification(null, E('p', [message]), 'info');
			return true;
		}).catch(function (error) {
			ui.addNotification(_('ExConnect'), E('p', [String(error.message || error)]), 'error');
			return false;
		});
	}
});
