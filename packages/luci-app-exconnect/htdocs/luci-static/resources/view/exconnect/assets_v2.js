'use strict';
'require form';
'require poll';
'require rpc';
'require ui';
'require view';
'require exconnect.client as client';

const updateAssets = rpc.declare({ object: 'exconnect', method: 'update_assets', reject: true });
const assetsStatus = rpc.declare({ object: 'exconnect', method: 'assets_status', reject: true });
const prepareUpload = rpc.declare({ object: 'exconnect', method: 'prepare_asset_upload', reject: true });
const discardUpload = rpc.declare({ object: 'exconnect', method: 'discard_asset_upload', params: [ 'token' ], reject: true });
const uploadAsset = rpc.declare({ object: 'exconnect', method: 'upload_asset', params: [ 'name', 'token' ], reject: true });

function checked(result) {
	if (!result || result.ok !== true)
		throw new Error(result && result.error || _('The operation failed.'));
	return result;
}

return view.extend({
	load: function () {
		return L.resolveDefault(assetsStatus(), null);
	},

	render: function (initialStatus) {
		const readOnly = !L.hasViewPermission();
		const controls = [];
		let uploading = false;
		let running = false;
		const status = E('p', { 'aria-live': 'polite' });
		const progress = E('progress', { 'style': 'width: 100%; display: none;', 'aria-label': _('Rule data transfer') });
		const uploadProgress = document.createTextNode('');

		function disableControls() {
			controls.forEach(function (control) { control.disabled = readOnly || uploading || running; });
		}

		function showStatus(result) {
			if (!result || result.ok !== true) {
				status.textContent = result && result.error || _('Could not read the rule data status.');
				return;
			}
			running = result.running === true;
			progress.style.display = running ? 'block' : 'none';
			if (Number(result.total_bytes) > 0) {
				progress.max = Number(result.total_bytes);
				progress.value = Number(result.downloaded_bytes) || 0;
			} else {
				progress.removeAttribute('value');
			}
			disableControls();
			if (result.error) {
				status.textContent = result.error;
				return;
			}
			const phases = {
				starting: _('Preparing rule data.'),
				downloading: _('Downloading rule data.'),
				validating: _('Checking rule data.'),
				installing: _('Installing rule data.')
			};
			if (running) {
				status.textContent = phases[result.phase] || _('Preparing rule data.');
				if (result.current_file)
					status.textContent += ' ' + result.current_file;
				if (Number(result.downloaded_bytes) > 0)
					status.textContent += ' ' + _('Received: %s MiB').format((Number(result.downloaded_bytes) / 1048576).toFixed(1));
			} else if (result.phase === 'completed') {
				status.textContent = _('Rule data was updated. Apply the configuration from Overview to load it.');
			} else {
				status.textContent = _('Ready to download or upload .dat lists.');
			}
		}

		function refreshStatus() {
			return L.resolveDefault(assetsStatus(), null).then(showStatus);
		}

		function reportError(error) {
			ui.addNotification(_('ExConnect'), E('p', [String(error.message || error)]), 'error');
		}

		const map = new form.Map('exconnect', _('Rule data'),
			_('Add Xray-compatible .dat lists from HTTPS sources or upload your own files. File size is limited by the available space on the router.'));
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
		url.rmempty = true;
		url.validate = function (sectionId, value) {
			return !value || client.validateHttps(sectionId, value);
		};
		url.value('https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat', _('RunetFreedom IP addresses'));
		url.value('https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat', _('RunetFreedom domains'));
		url.description = _('Leave the URL empty for a list uploaded from your computer.');

		const upload = assets.option(form.Button, '_upload', _('Local file'));
		upload.inputtitle = _('Upload .dat');
		upload.inputstyle = 'action';
		upload.editable = true;
		const renderUpload = upload.renderWidget;
		upload.renderWidget = function () {
			const widget = renderUpload.apply(this, arguments);
			const button = widget.querySelector('button');
			if (button) {
				controls.push(button);
				disableControls();
			}
			return widget;
		};
		upload.onclick = function (event, sectionId) {
			if (readOnly || uploading || running)
				return;
			const name = map.data.get('exconnect', sectionId, 'name');
			if (!/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,96}\.dat$/.test(name || '')) {
				reportError(new Error(_('Save a valid .dat filename before uploading.')));
				return;
			}
			let uploadToken;
			uploading = true;
			uploadProgress.data = '';
			disableControls();
			return prepareUpload().then(checked).then(function (prepared) {
				uploadToken = prepared.token;
				return ui.uploadFile(prepared.path, uploadProgress).then(function () {
					return uploadAsset(name, prepared.token);
				});
			}).then(checked).then(function () {
				return refreshStatus();
			}).catch(reportError).finally(function () {
				uploading = false;
				uploadProgress.data = '';
				disableControls();
				if (uploadToken)
					return L.resolveDefault(discardUpload(uploadToken), null);
			});
		};

		return map.render().then(function (node) {
			const download = E('button', {
				'type': 'button',
				'class': 'cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, function () {
					if (readOnly || uploading || running)
						return;
					running = true;
					disableControls();
					return updateAssets().then(checked).then(refreshStatus).catch(function (error) {
						running = false;
						disableControls();
						reportError(error);
					});
				})
			}, [_('Download rule data')]);
			controls.push(download);
			showStatus(initialStatus);
			disableControls();
			poll.add(refreshStatus, 1);
			return E([
				node,
				E('div', { 'class': 'cbi-section' }, [
					E('p', [_('Save and apply the filenames and sources before downloading or uploading. Reference a file and its tag in Routing, for example ext:geosite-custom.dat:tag.')]),
					download, ' ', uploadProgress, progress, status
				])
			]);
		});
	}
});
