#!/usr/bin/env bash
# Build wslc-remote_<version>_all.deb into packaging/deb/dist/ (needs dpkg-deb).
# Usage: packaging/deb/build.sh [version]     (default: <VERSION>+git<date>.<sha>)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
version="${1:-$(cat "$here/VERSION")+git$(date -u +%Y%m%d).$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo local)}"

stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
install -d "$stage/DEBIAN" "$stage/usr/bin" "$stage/usr/share/doc/wslc-remote"
install -m 0755 "$repo/wslc" "$stage/usr/bin/wslc"
ln -s wslc "$stage/usr/bin/container"
install -m 0755 "$here/files/wslc-build-unfsd" "$stage/usr/bin/wslc-build-unfsd"
install -m 0644 "$repo/README.md" "$stage/usr/share/doc/wslc-remote/README.md"
install -m 0644 "$repo/LICENSE" "$stage/usr/share/doc/wslc-remote/copyright"
printf 'wslc-remote (%s) unstable; urgency=low\n\n  * Snapshot build.\n\n -- wslc-remote maintainers <noreply@example.invalid>  %s\n' \
  "$version" "$(date -uR)" | gzip -9n >"$stage/usr/share/doc/wslc-remote/changelog.gz"
sed "s/@VERSION@/$version/" "$here/DEBIAN/control.in" >"$stage/DEBIAN/control"
install -m 0755 "$here/DEBIAN/postinst" "$stage/DEBIAN/postinst"

mkdir -p "$here/dist"
out="$here/dist/wslc-remote_${version}_all.deb"
dpkg-deb --root-owner-group --build "$stage" "$out" >/dev/null
echo "$out"
