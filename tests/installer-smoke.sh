#!/bin/sh
set -eu

installer=${1:?Usage: installer-smoke.sh INSTALLER APK_ARCHIVE}
archive=${2:?Usage: installer-smoke.sh INSTALLER APK_ARCHIVE}
test -f "$installer"
test -f "$archive"

# Exercise the real installer and apk without live GitHub credentials.
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
trap 'exit 1' HUP INT TERM
cat > "$fixtures/curl" <<'MOCK_CURL'
#!/bin/sh
set -eu

fail() {
    printf 'Installer smoke test: %s\n' "$*" >&2
    exit 1
}

output=
url=
header=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -H) [ "$2" = @- ] || fail 'GitHub header must come from stdin'; IFS= read -r header; shift ;;
        -o) output=$2; shift ;;
        --proto|--proto-redir|--connect-timeout|--retry) shift ;;
        -q|-fsSL) ;;
        https://*) url=$1 ;;
        *) fail "unexpected curl argument: $1" ;;
    esac
    shift
done

[ "$header" = 'Authorization: Bearer installer-smoke-token' ] || fail 'missing test authorization header'
[ -n "$output" ] || fail 'missing output file'
api=https://api.github.com/repos/exg0n/ExConnect
case "$url" in
    "$api/actions/workflows/openwrt.yml/runs?branch=main&event=push&status=success&per_page=1")
        printf '%s\n' '{"workflow_runs":[{"id":101}]}' > "$output"
        ;;
    "$api/actions/runs/101/artifacts?name=exconnect-openwrt-25.12.5&per_page=1")
        printf '%s\n' '{"artifacts":[{"id":202,"expired":false}]}' > "$output"
        ;;
    "$api/actions/artifacts/202/zip")
        cp "$EXCONNECT_SMOKE_ARCHIVE" "$output"
        ;;
    *) fail "unexpected curl URL: $url" ;;
esac
MOCK_CURL

# Keep offline-root semantics for package hooks in the isolated chroot.
cat > "$fixtures/apk" <<'PACKAGE_MANAGER'
#!/bin/sh
exec /usr/bin/apk --preserve-env "$@"
PACKAGE_MANAGER
chmod 700 "$fixtures/curl" "$fixtures/apk"

printf '%s\n' installer-smoke-token |
    EXCONNECT_SMOKE_ARCHIVE="$archive" PATH="$fixtures:$PATH" IPKG_INSTROOT=/ /bin/sh "$installer"
