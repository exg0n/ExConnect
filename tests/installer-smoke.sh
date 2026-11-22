#!/bin/sh
set -eu

installer=${1:?Usage: installer-smoke.sh INSTALLER APK_ARCHIVE}
archive=${2:?Usage: installer-smoke.sh INSTALLER APK_ARCHIVE}
test -f "$installer"
test -f "$archive"

# Substitute the candidate packages for the current public release.
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
trap 'exit 1' HUP INT TERM
cat > "$fixtures/wget" <<'MOCK_WGET'
#!/bin/sh
set -eu

if [ "$#" -eq 5 ] && [ "$1" = -T ] && [ "$3" = -O ] &&
    [ "$5" = 'https://github.com/exg0n/ExConnect/releases/latest/download/exconnect-openwrt-25.12.5.zip' ]; then
    cp "$EXCONNECT_SMOKE_ARCHIVE" "$4"
else
    exec "$EXCONNECT_SMOKE_WGET" "$@"
fi
MOCK_WGET

# Keep offline-root semantics for package hooks in the isolated chroot.
cat > "$fixtures/apk" <<'PACKAGE_MANAGER'
#!/bin/sh
exec /usr/bin/apk --preserve-env "$@"
PACKAGE_MANAGER
chmod 700 "$fixtures/wget" "$fixtures/apk"

EXCONNECT_SMOKE_WGET=$(command -v wget)
export EXCONNECT_SMOKE_WGET
EXCONNECT_SMOKE_ARCHIVE="$archive" PATH="$fixtures:$PATH" IPKG_INSTROOT=/ /bin/sh "$installer"
