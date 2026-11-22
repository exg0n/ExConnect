#!/bin/sh
set -eu

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" = 0 ] || fail 'Run this installer as root on the router.'
grep -qx "DISTRIB_RELEASE='25.12.5'" /etc/openwrt_release || fail 'ExConnect requires OpenWrt 25.12.5.'
IFS= read -r token && [ -n "$token" ] || fail 'A GitHub token is required for this private repository.'

api=https://api.github.com/repos/exg0n/ExConnect
artifact_name=exconnect-openwrt-25.12.5
workdir=$(mktemp -d /tmp/exconnect-install.XXXXXX)
trap 'rm -rf "$workdir"' EXIT
trap 'exit 1' HUP INT TERM

github_get() {
    printf 'Authorization: Bearer %s\n' "$token" |
        curl -q -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 15 --retry 2 \
            -H @- -o "$2" "$api/$1"
}

github_get 'actions/workflows/openwrt.yml/runs?branch=main&event=push&status=success&per_page=1' "$workdir/runs.json"
run_id=$(jsonfilter -i "$workdir/runs.json" -e '@.workflow_runs[0].id') || run_id=
case "$run_id" in ''|*[!0-9]*) fail 'No successful ExConnect build on main. Check GitHub Actions.' ;; esac

github_get "actions/runs/$run_id/artifacts?name=$artifact_name&per_page=1" "$workdir/artifacts.json"
artifact_id=$(jsonfilter -i "$workdir/artifacts.json" -e '@.artifacts[0].id') || artifact_id=
case "$artifact_id" in ''|*[!0-9]*) fail 'The package artifact is missing. Check GitHub Actions.' ;; esac
[ "$(jsonfilter -i "$workdir/artifacts.json" -e '@.artifacts[0].expired')" = false ] || fail 'The package artifact expired. A fresh build on main is required.'

github_get "actions/artifacts/$artifact_id/zip" "$workdir/packages.zip"
unset token
cd "$workdir"
unzip -q packages.zip 'exconnect-[0-9]*.apk' 'luci-app-exconnect-[0-9]*.apk'
set -- ./exconnect-[0-9]*.apk ./luci-app-exconnect-[0-9]*.apk
[ "$#" -eq 2 ] && [ -f "$1" ] && [ -f "$2" ] || fail 'Expected one APK for ExConnect and one for LuCI.'
apk add --allow-untrusted "$@"
printf '\nExConnect installed. Open Services -> ExConnect in LuCI.\n'
