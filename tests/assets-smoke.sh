#!/bin/sh
set -eu

if [ "${1:-}" != --disposable-openwrt ]; then
	printf '%s\n' 'Run only in a disposable OpenWrt test environment: sh assets-smoke.sh --disposable-openwrt' >&2
	exit 2
fi

config=/etc/config/exconnect
asset_root=/etc/exconnect
runtime=/var/run/exconnect
fixture=$(mktemp -d)
worker_pid=
upload_job=
bad_job=
asset_setup=0

cleanup() {
	if [ -n "$worker_pid" ]; then
		kill "$worker_pid" 2>/dev/null || :
		wait "$worker_pid" 2>/dev/null || :
	fi
	[ ! -f "$fixture/config" ] || cp "$fixture/config" "$config"
	if [ "$asset_setup" -eq 1 ]; then
		rm -rf "$asset_root/geo"
		[ ! -d "$fixture/original-geo" ] || mv "$fixture/original-geo" "$asset_root/geo"
	fi
	for task in "$upload_job" "$bad_job" "$(cat "$runtime/assets-current" 2>/dev/null || :)"; do
		case "$task" in /etc/exconnect/geo-update.??????) rm -rf "$task" ;; esac
	done
	rm -f "$runtime/assets-current" "$runtime/last_error"
	rm -rf "$fixture"
}

fail() {
	printf '%s\n' "$*" >&2
	[ ! -f "$fixture/update.log" ] || cat "$fixture/update.log" >&2
	exit 1
}

if [ -e "$runtime/assets-current" ]; then
	printf '%s\n' 'A rule data task already exists.' >&2
	rm -rf "$fixture"
	exit 1
fi
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
cp "$config" "$fixture/config"
mkdir -p "$asset_root"
[ ! -d "$asset_root/geo" ] || mv "$asset_root/geo" "$fixture/original-geo"
asset_setup=1
mkdir "$asset_root/geo" "$fixture/tools"

# A valid GeoSite list with a large unknown protobuf field exercises files above
# the former 128 MiB limit without generating millions of domain rules.
printf '\022\200\200\300\100' > "$fixture/large.dat"
dd if=/dev/zero bs=1048576 count=129 >> "$fixture/large.dat" 2>/dev/null
printf '\012\033\012\007FIXTURE\022\020\010\003\022\014example.test' >> "$fixture/large.dat"
printf '\012\033\012\007FIXTURE\022\020\010\003\022\014example.test' > "$fixture/small.dat"
cp "$fixture/small.dat" "$asset_root/geo/previous.dat"

cat > "$fixture/tools/curl" <<'EOF'
#!/bin/sh
set -eu
output=
for argument do
	case "$argument" in
		--max-filesize|--max-filesize=*) exit 90 ;;
	esac
done
while [ "$#" -gt 0 ]; do
	case "$1" in
		--output|-o) output=$2; shift ;;
	esac
	shift
done
[ -n "$output" ]
if [ -e "$EXCONNECT_ASSET_FIXTURE/fail-download" ]; then
	printf '%s\n' 'partial download' > "$output"
	exit 23
fi
if [ -e "$EXCONNECT_ASSET_FIXTURE/pause-download" ]; then
	touch "$EXCONNECT_ASSET_FIXTURE/download-started"
	attempt=0
	while [ ! -e "$EXCONNECT_ASSET_FIXTURE/resume-download" ]; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt 20 ] || exit 28
		sleep 1
	done
fi
cp "$EXCONNECT_ASSET_FIXTURE/large.dat" "$output"
EOF
chmod 700 "$fixture/tools/curl"

cat > "$config" <<'EOF'
config service 'main'
	option enabled '0'
	option mode 'local'
	option default_action 'direct'
config asset 'site_data'
	option name 'custom-geosite.dat'
	option url 'https://example.test/custom.dat'
EOF

update_assets() {
	EXCONNECT_ASSET_FIXTURE="$fixture" PATH="$fixture/tools:$PATH" \
		/usr/libexec/exconnect/control update_assets
}

update_assets > "$fixture/update.log" 2>&1 || fail 'A valid DAT above 128 MiB was rejected.'
cmp "$fixture/large.dat" "$asset_root/geo/custom-geosite.dat" || fail 'The large DAT was truncated.'
cmp "$fixture/small.dat" "$asset_root/geo/previous.dat" || fail 'Unrelated local data was removed.'

touch "$fixture/fail-download"
if update_assets > "$fixture/update.log" 2>&1; then
	fail 'A partial failed download was accepted.'
fi
rm "$fixture/fail-download"
cmp "$fixture/large.dat" "$asset_root/geo/custom-geosite.dat" || fail 'A failed download replaced active data.'

touch "$fixture/pause-download"
update_assets > "$fixture/update.log" 2>&1 &
worker_pid=$!
attempt=0
until [ -e "$fixture/download-started" ]; do
	attempt=$((attempt + 1))
	[ "$attempt" -lt 10 ] || fail 'The staged download did not start.'
	kill -0 "$worker_pid" 2>/dev/null || fail 'The staged worker exited early.'
	sleep 1
done
# A network operation must not occupy the service-control lock.
flock -n "$runtime/control.lock" true || fail 'The download blocked service control.'
uci set exconnect.site_data.url=https://example.test/changed.dat
uci commit exconnect
touch "$fixture/resume-download"
if wait "$worker_pid"; then
	worker_pid=
	fail 'A download installed data after its source changed.'
fi
worker_pid=
cmp "$fixture/large.dat" "$asset_root/geo/custom-geosite.dat" || fail 'A source change replaced active data.'

# Upload reservations permit writing only the reserved file. Reject traversal
# before any background service is registered.
printf '%s\n' '{}' | /usr/libexec/rpcd/exconnect call prepare_asset_upload > "$fixture/upload.json"
[ "$(jsonfilter -i "$fixture/upload.json" -e '@.ok')" = true ]
token=$(jsonfilter -i "$fixture/upload.json" -e '@.token')
upload_path=$(jsonfilter -i "$fixture/upload.json" -e '@.path')
[ "$upload_path" = "$runtime/uploads/upload.$token" ]
cp "$fixture/small.dat" "$upload_path"
printf '{"name":"../outside.dat","token":"%s"}\n' "$token" |
	/usr/libexec/rpcd/exconnect call upload_asset > "$fixture/rejected-upload.json"
[ "$(jsonfilter -i "$fixture/rejected-upload.json" -e '@.ok')" = false ] || fail 'An upload filename escaped its directory.'
cmp "$fixture/small.dat" "$upload_path" || fail 'A rejected upload consumed its reserved file.'
rm "$upload_path"

# Execute the installed worker with completed upload fixtures, without procd in
# this disposable chroot. The normal import/validation/commit path is unchanged.
uci set exconnect.local_data=asset
uci set exconnect.local_data.name=uploaded.dat
uci commit exconnect
upload_job=$(mktemp -d "$asset_root/geo-update.XXXXXX")
ucode /usr/libexec/exconnect/generate.uc asset_snapshot > "$upload_job/config.snapshot"
: > "$upload_job/sources"
printf '%s\n' uploaded.dat > "$upload_job/upload-name"
cp "$fixture/small.dat" "$upload_job/upload.dat"
/usr/libexec/exconnect/assets run "$upload_job" > "$fixture/update.log" 2>&1 || fail 'A valid local DAT upload was rejected.'
cmp "$fixture/small.dat" "$asset_root/geo/uploaded.dat"
cmp "$fixture/large.dat" "$asset_root/geo/custom-geosite.dat"

bad_job=$(mktemp -d "$asset_root/geo-update.XXXXXX")
ucode /usr/libexec/exconnect/generate.uc asset_snapshot > "$bad_job/config.snapshot"
: > "$bad_job/sources"
printf '%s\n' uploaded.dat > "$bad_job/upload-name"
printf '%s\n' 'not a DAT list' > "$bad_job/upload.dat"
if /usr/libexec/exconnect/assets run "$bad_job" > "$fixture/update.log" 2>&1; then
	fail 'A malformed local DAT upload was accepted.'
fi
cmp "$fixture/small.dat" "$asset_root/geo/uploaded.dat" || fail 'A malformed upload replaced active data.'

printf '%s\n' 'Large DAT downloads and local uploads preserve active data on failure.'
