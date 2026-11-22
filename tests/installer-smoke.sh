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

fail() {
    printf 'Installer smoke test: %s\n' "$*" >&2
    exit 1
}

output=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -O) output=$2; shift ;;
        -T) shift ;;
        https://*) url=$1 ;;
        *) fail "unexpected wget argument: $1" ;;
    esac
    shift
done

[ -n "$output" ] || fail 'missing output file'
[ "$url" = 'https://github.com/exg0n/ExConnect/releases/latest/download/exconnect-openwrt-25.12.5.zip' ] ||
    fail "unexpected wget URL: $url"
cp "$EXCONNECT_SMOKE_ARCHIVE" "$output"
MOCK_WGET

# Keep offline-root semantics for package hooks in the isolated chroot.
cat > "$fixtures/apk" <<'PACKAGE_MANAGER'
#!/bin/sh
exec /usr/bin/apk --preserve-env "$@"
PACKAGE_MANAGER
chmod 700 "$fixtures/wget" "$fixtures/apk"

EXCONNECT_SMOKE_ARCHIVE="$archive" PATH="$fixtures:$PATH" IPKG_INSTROOT=/ /bin/sh "$installer"
