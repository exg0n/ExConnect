'use strict';
'require form';
'require baseclass';
'require exconnect.client as client';

return baseclass.extend({
	addTo: function (map) {
		const subscriptions = map.section(form.GridSection, 'subscription', _('Subscription sources'),
			_('Deleting a subscription removes its imported profiles. If one of them is selected, it becomes a manual profile.'));
		subscriptions.anonymous = true;
		subscriptions.addremove = true;
		const removeSubscription = subscriptions.handleRemove;
		subscriptions.handleRemove = function (sectionId, event) {
			const config = map.config;
			const selected = map.data.get(config, 'main', 'profile');
			map.data.sections(config, 'profile').forEach(function (profile) {
				if (profile.subscription !== sectionId)
					return;

				const profileId = profile['.name'];
				if (profileId === selected) {
					map.data.unset(config, profileId, 'subscription');
					map.data.unset(config, profileId, 'stale');
				} else {
					map.data.remove(config, profileId);
				}
			});
			return removeSubscription.call(this, sectionId, event);
		};

		const name = subscriptions.option(form.Value, 'name', _('Subscription name'));
		name.rmempty = false;

		const url = subscriptions.option(form.Value, 'url', _('HTTPS URL'));
		url.modalonly = true;
		url.password = true;
		url.rmempty = false;
		url.validate = client.validateHttps;

		const refresh = subscriptions.option(form.Button, '_refresh', _('Refresh'));
		refresh.modalonly = false;
		refresh.editable = true;
		refresh.inputtitle = _('Refresh subscription');
		refresh.inputstyle = 'action';
		refresh.onclick = function (event, sectionId) {
			return client.perform(function () {
				return client.refreshSubscription(sectionId);
			}, function (result) {
				return _('Number of subscription profiles: %s').format(Number(result.count) || 0);
			});
		};
	}
});
