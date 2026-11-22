#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sdk_dir=$(cd "${1:?Usage: bash scripts/build-openwrt.sh SDK_DIR [OUTPUT_DIR]}" && pwd)
output_dir=${2:-"$project_dir/dist"}
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)

cd "$sdk_dir"
test -x scripts/feeds
for package in exconnect luci-app-exconnect; do
    link="package/$package"
    if [ -e "$link" ] || [ -L "$link" ]; then
        if [ "$(readlink -f "$link")" != "$project_dir/packages/$package" ]; then
            printf 'Package path already exists: %s\n' "$link" >&2
            exit 1
        fi
    else
        ln -s "$project_dir/packages/$package" "$link"
    fi
done

./scripts/feeds update -a
./scripts/feeds install -a
touch .config
if ! grep -qx 'CONFIG_PACKAGE_exconnect=m' .config ||
   ! grep -qx 'CONFIG_PACKAGE_luci-app-exconnect=m' .config; then
    sed -i -E '/^(# )?CONFIG_PACKAGE_(exconnect|luci-app-exconnect)(=| is not set)/d' .config
    printf '%s\n' 'CONFIG_PACKAGE_exconnect=m' 'CONFIG_PACKAGE_luci-app-exconnect=m' >> .config
fi
make defconfig
for package in exconnect luci-app-exconnect; do
    grep -Eq "^CONFIG_PACKAGE_${package}=[my]$" .config || {
        printf 'OpenWrt dependency configuration excluded %s\n' "$package" >&2
        exit 1
    }
    marker=$(mktemp)
    trap 'rm -f "$marker"' EXIT
    make "package/$package/clean"
    make -j"${JOBS:-2}" "package/$package/compile" V=s
    find bin -type f -newer "$marker" \( -name "${package}-[0-9]*.apk" -o -name "${package}-i18n-*.apk" -o -name "luci-i18n-exconnect-*.apk" \) -exec cp -t "$output_dir" -- {} +
    find bin -type f -newer "$marker" -name "${package}-[0-9]*.apk" -print -quit | grep -q .
    rm -f "$marker"
    trap - EXIT
done

printf 'Packages saved in %s\n' "$output_dir"
