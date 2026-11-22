#!/usr/bin/env bash
set -euo pipefail

rootfs=$(realpath "${1:?Usage: package-install-ci.sh OPENWRT_ROOTFS APK_DIRECTORY}")
package_dir=${2:?Usage: package-install-ci.sh OPENWRT_ROOTFS APK_DIRECTORY}
project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

set -- "$package_dir"/exconnect-[0-9]*.apk "$package_dir"/luci-app-exconnect-[0-9]*.apk
test "$#" -eq 2
test -f "$1"
test -f "$2"
test -f "$rootfs/etc/openwrt_release"
test "$rootfs" != /

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
python3 -m zipfile -c "$workdir/exconnect-apks.zip" "$@"
sudo mkdir -p "$rootfs/dev" "$rootfs/proc" "$rootfs/tmp/lock"
sudo cp -L --remove-destination /etc/resolv.conf "$rootfs/etc/resolv.conf"
sudo cp "$workdir/exconnect-apks.zip" "$project_dir/scripts/install-openwrt.sh" \
    "$project_dir"/tests/{installer-smoke,runtime,proxy-smoke}.sh "$rootfs/tmp/"

sudo unshare --mount --propagation private bash -e -s -- "$rootfs" <<'HOST'
rootfs=$1
mount --bind /dev "$rootfs/dev"
mount -t proc proc "$rootfs/proc"
chroot "$rootfs" /bin/sh -e -s <<'OPENWRT'
# Treat the chroot as an offline image so package hooks do not start services or load modules.
/bin/sh /tmp/installer-smoke.sh /tmp/install-openwrt.sh /tmp/exconnect-apks.zip
for package in exconnect luci-app-exconnect xray-core luci-light uhttpd kmod-nft-tproxy; do
    apk info -e "$package"
done
for tool in xray ucode curl nft ip ss flock; do
    command -v "$tool"
done
test "$(uci -q get exconnect.main.enabled)" = 0
test -x /etc/init.d/exconnect
test -x /usr/libexec/exconnect/control
test -x /usr/libexec/exconnect/probe
test -x /usr/libexec/exconnect/run
test -x /usr/libexec/rpcd/exconnect
test -x /usr/libexec/rpcd/exconnect-subscriptions
test -s /usr/share/luci/menu.d/luci-app-exconnect.json
test -s /usr/share/rpcd/acl.d/luci-app-exconnect.json
test -s /usr/lib/lua/luci/i18n/exconnect.ru.lmo
test -s /www/luci-static/resources/exconnect/client.js
test -s /www/luci-static/resources/view/exconnect/overview.js
test -s /www/luci-static/resources/view/exconnect/diagnostics.js
test -s /www/luci-static/resources/exconnect/subscriptions.js
IPKG_INSTROOT=/ apk --preserve-env add coreutils-base64 diffutils
/bin/sh /tmp/runtime.sh
OPENWRT
unshare --net bash -e -c '
    ip link set lo up
    chroot "$1" /bin/sh /tmp/proxy-smoke.sh --disposable-openwrt
' bash "$rootfs"
HOST
