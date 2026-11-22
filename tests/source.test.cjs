const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

const packages = path.resolve(__dirname, '../packages');
const backend = path.join(packages, 'exconnect');
const luci = path.join(packages, 'luci-app-exconnect');
const views = path.join(luci, 'htdocs/luci-static/resources/view');

function read(...parts) {
    return fs.readFileSync(path.join(...parts), 'utf8');
}

function filesUnder(directory) {
    return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
        const filename = path.join(directory, entry.name);
        return entry.isDirectory() ? filesUnder(filename) : [filename];
    });
}

function run(executable, args) {
    const result = spawnSync(executable, args, { encoding: 'utf8' });
    assert.ifError(result.error);
    assert.equal(result.status, 0, [executable, ...args, result.stderr].join(' '));
}

function readCatalog(source) {
    const catalog = new Map();

    for (const entry of source.split(/\r?\n\r?\n/)) {
        let msgid = '';
        let msgstr = '';
        let field;

        for (const line of entry.split(/\r?\n/)) {
            const named = /^(msgid|msgstr) (".*")$/.exec(line);
            if (named) field = named[1];
            const quoted = named?.[2] ?? (/^"/.test(line) ? line : null);
            if (quoted && field === 'msgid') msgid += JSON.parse(quoted);
            if (quoted && field === 'msgstr') msgstr += JSON.parse(quoted);
        }

        if (msgid && !/^#,.*\bfuzzy\b/m.test(entry)) catalog.set(msgid, msgstr);
    }

    return catalog;
}

function readMenu() {
    return JSON.parse(read(luci, 'root/usr/share/luci/menu.d/luci-app-exconnect.json'));
}

test('OpenWrt packages reference the service and preserve its UCI configuration', () => {
    const service = read(backend, 'Makefile');
    const app = read(luci, 'Makefile');

    assert.match(service, /PKG_NAME\s*:?=\s*exconnect\b/);
    assert.match(service, /\+xray-core\b/);
    assert.match(service, /\/etc\/config\/exconnect\b/);
    assert.match(app, /\+exconnect\b/);
    assert.match(app, /\bpo2lmo\b.*\bexconnect\.ru\.lmo\b/);
    assert.ok(fs.existsSync(path.join(backend, 'files/etc/init.d/exconnect')));
    assert.ok(fs.existsSync(path.join(backend, 'files/usr/libexec/rpcd/exconnect')));
    for (const entry of ['usr/libexec/exconnect/subscriptions.uc', 'usr/libexec/rpcd/exconnect-subscriptions']) {
        assert.ok(service.includes(`./files/${entry}`));
        assert.ok(fs.existsSync(path.join(backend, 'files', entry)));
    }

    const config = read(backend, 'files/etc/config/exconnect');
    assert.match(config, /^config\s+service\s+['"]?main\b/m);
    assert.match(config, /^\s*option\s+enabled\s+['"]?0\b/m);
});

test('LuCI menu resolves each view and requires the app ACL', () => {
    const menu = readMenu();
    const parent = 'admin/services/exconnect';
    assert.ok(menu[parent].depends.acl.includes('luci-app-exconnect'));
    for (const page of ['overview', 'profiles', 'subscriptions', 'routing', 'assets', 'settings']) {
        const entry = menu[`${parent}/${page}`];
        assert.equal(entry.action.type, 'view', page);
        assert.ok(fs.existsSync(path.join(views, `${entry.action.path}.js`)), page);
    }
});

test('LuCI distinguishes read-only status and write operations', () => {
    const filename = 'root/usr/share/rpcd/acl.d/luci-app-exconnect.json';
    const acl = JSON.parse(read(luci, filename))['luci-app-exconnect'];
    const { read: readonly, write } = acl;
    assert.ok(readonly.uci.includes('exconnect'));
    assert.ok(write.uci.includes('exconnect'));
    assert.deepEqual(readonly.ubus.exconnect, ['status']);
    for (const method of ['apply', 'stop', 'update_assets', 'validate']) {
        assert.ok(write.ubus.exconnect.includes(method), method);
    }
    assert.ok(!write.ubus.exconnect.includes('*'));
    assert.equal(readonly.ubus['exconnect-subscriptions'], undefined);
    assert.deepEqual(write.ubus['exconnect-subscriptions'], ['refresh']);
});

test('LuCI modules compile in the browser-style wrapper', () => {
    const scripts = filesUnder(path.join(luci, 'htdocs')).filter(file => file.endsWith('.js'));
    assert.ok(scripts.length > 0);
    for (const filename of scripts) {
        assert.doesNotThrow(() => new Function(read(filename)), filename);
    }
});

test('LuCI handles both successful and unsuccessful service actions', async () => {
    const notifications = [];
    const source = read(luci, 'htdocs/luci-static/resources/exconnect/client.js');
    const client = vm.runInNewContext(`(function () { ${source}\n })()`, {
        baseclass: { extend: object => object },
        rpc: { declare: () => undefined },
        ui: { addNotification: (title, body, severity) => notifications.push({ title, body, severity }) },
        E: (_tag, children) => children.join(''),
        _: input => input,
    });

    assert.equal(await client.perform(async () => ({ ok: true }), 'Saved'), true);
    assert.deepEqual(notifications.pop(), { title: null, body: 'Saved', severity: 'info' });
    assert.equal(await client.perform(async () => ({ ok: false, error: 'Invalid profile' }), 'Saved'), false);
    assert.deepEqual(notifications.pop(), { title: 'ExConnect', body: 'Invalid profile', severity: 'error' });
    assert.equal(await client.perform(async () => { throw new Error('Unavailable'); }, 'Saved'), false);
    assert.deepEqual(notifications.pop(), { title: 'ExConnect', body: 'Unavailable', severity: 'error' });
});

test('Russian catalog translates LuCI menu labels and literal UI strings', () => {
    const catalog = readCatalog(read(luci, 'po/ru/exconnect.po'));
    const labels = new Set(Object.values(readMenu()).map(entry => entry.title).filter(Boolean));
    const scripts = filesUnder(path.join(luci, 'htdocs')).filter(file => file.endsWith('.js'));

    for (const filename of scripts) {
        const strings = read(filename).matchAll(/\b_\(\s*('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")\s*\)/g);
        for (const [, literal] of strings) labels.add(new Function(`return ${literal}`)());
    }

    assert.ok(labels.size > 5);
    assert.deepEqual([...labels].filter(label => !catalog.get(label)), []);
    assert.match([...catalog.values()].join(' '), /[А-Яа-яЁё]/);
});

test('OpenWrt shell entry points parse', { skip: process.platform === 'win32' }, () => {
    const scripts = filesUnder(path.join(backend, 'files')).filter(file => /^#!\/bin\/sh\b/.test(read(file)));
    scripts.push(path.join(__dirname, 'runtime.sh'));
    for (const filename of scripts) run('sh', ['-n', filename]);
});
