'use strict';
'require form';
'require view';

return view.extend({
	render: function () {
		const map = new form.Map('exconnect', _('Routing'),
			_('Rules are evaluated from top to bottom. The first match wins. Set the action for unmatched traffic in Settings.'));
		const main = map.section(form.NamedSection, 'main', 'service', _('Routing format'));
		const mode = main.option(form.ListValue, 'routing_mode', _('Rule editor'),
			_('Only the selected editor supplies active rules. Switching editors keeps existing rules.'));
		mode.value('table', _('Rule table'));
		mode.value('text', 'RoutingA');
		mode.default = 'table';
		mode.rmempty = false;

		const text = main.option(form.TextValue, 'routing_text', _('RoutingA rules'),
			_('Use default: direct and domain(...), geoip(...), ip(...) or protocol(...), followed by ->direct, ->proxy or ->block. Lines starting with # are comments.'));
		text.rows = 18;
		text.monospace = true;
		text.placeholder = 'default: direct\nprotocol(bittorrent)->direct\ndomain(domain:example.org)->proxy\ngeoip(telegram)->proxy';
		text.depends('routing_mode', 'text');
		text.retain = true;

		const rules = map.section(form.GridSection, 'rule', _('Traffic rules'));
		rules.anonymous = true;
		rules.addremove = true;
		rules.sortable = true;

		const name = rules.option(form.Value, 'name', _('Rule name'));
		name.rmempty = false;

		const enabled = rules.option(form.Flag, 'enabled', _('Enabled'));
		enabled.default = enabled.enabled;
		enabled.rmempty = false;

		const action = rules.option(form.ListValue, 'action', _('Action'));
		action.value('proxy', _('Proxy'));
		action.value('direct', _('Direct'));
		action.value('block', _('Block'));
		action.default = 'proxy';
		action.rmempty = false;

		const domains = rules.option(form.DynamicList, 'domains', _('Domains'),
			_('Use Xray domain syntax such as domain:example.org, geosite:ru or ext:geosite-custom.dat:ru.'));
		domains.modalonly = true;

		const ips = rules.option(form.DynamicList, 'ips', _('IP addresses'),
			_('Use Xray IP syntax such as 203.0.113.0/24, geoip:ru or ext:geoip-custom.dat:ru. A domain or IP match can trigger the rule.'));
		ips.modalonly = true;

		return map.render();
	}
});
