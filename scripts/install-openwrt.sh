#!/bin/sh
set -eu

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" = 0 ] || fail 'Run this installer as root on the router.'
grep -qx "DISTRIB_RELEASE='25.12.5'" /etc/openwrt_release || fail 'ExConnect requires OpenWrt 25.12.5.'

archive_url=https://raw.githubusercontent.com/exg0n/ExConnect/openwrt-packages/exconnect-openwrt-25.12.5.zip
workdir=$(mktemp -d /tmp/exconnect-install.XXXXXX)
trap 'rm -rf "$workdir"' EXIT
trap 'exit 1' HUP INT TERM

cd "$workdir"
wget -T 30 -O packages.zip "$archive_url" || fail 'Could not download ExConnect packages from raw.githubusercontent.com.'
apk update
command -v unzip >/dev/null 2>&1 || apk add unzip
unzip -q packages.zip 'exconnect-[0-9]*.apk' 'luci-app-exconnect-[0-9]*.apk'
set -- ./exconnect-[0-9]*.apk ./luci-app-exconnect-[0-9]*.apk
[ "$#" -eq 2 ] && [ -f "$1" ] && [ -f "$2" ] || fail 'Expected one APK for ExConnect and one for LuCI.'
apk add --allow-untrusted "$@"
printf '\nExConnect installed. Open Services -> ExConnect in LuCI.\n'
