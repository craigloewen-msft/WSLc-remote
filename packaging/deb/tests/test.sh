#!/usr/bin/env bash
# Build the .deb, then install/exercise/remove it. Installing needs root and
# modifies the system, so run it in a container or VM:
#   docker run --rm -v "$PWD":/src -w /src debian:stable packaging/deb/tests/test.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
check() { local d="$1"; shift; "$@" >/dev/null 2>&1 && pass "$d" || fail "$d"; }

deb="$("$here/../build.sh")"; echo "built $deb"

# Static checks
dpkg-deb -I "$deb" >/dev/null && pass "control metadata readable"
contents="$(dpkg-deb -c "$deb")"
grep -q ' ./usr/bin/wslc$' <<<"$contents" && pass "ships /usr/bin/wslc" || fail "missing wslc"
grep -q 'container -> wslc' <<<"$contents" && pass "ships container alias" || fail "missing alias"
for f in "$here"/../files/wslc-build-unfsd "$here"/../../../wslc "$here"/../build.sh "$here"/../DEBIAN/postinst; do
  bash -n "$f" 2>/dev/null || sh -n "$f" || fail "syntax $f"
done; pass "shell syntax"
command -v shellcheck >/dev/null && { shellcheck -S warning "$here"/../files/wslc-build-unfsd "$here"/../build.sh && pass shellcheck; } || true
"$here/net.sh" && pass "network detection tests" || fail "network detection tests"
command -v lintian >/dev/null && { lintian --no-tag-display-limit "$deb" || true; }

[[ $EUID -eq 0 ]] || { echo "not root: skipping install tests"; exit 0; }

# Install (dpkg -i then resolve deps the way apt would)
export DEBIAN_FRONTEND=noninteractive
dpkg -i "$deb" >/dev/null 2>&1 || apt-get install -y -f >/dev/null
check "package installed" dpkg -s wslc-remote
check "wslc runs (_help)" wslc _help
check "container alias runs" container _help

# Passthrough goes to $WSLC; use a fake wslc.exe to prove the wiring.
fake="$(mktemp -d)/wslc.exe"
printf '#!/bin/sh\necho "fake-wslc $*"\n' >"$fake"; chmod +x "$fake"
[[ "$(WSLC="$fake" wslc images -q)" == "fake-wslc images -q" ]] && pass "passthrough to real wslc" || fail "passthrough"
[[ "$(WSLC="$fake" container ps)" == "fake-wslc ps" ]] && pass "alias passthrough" || fail "alias passthrough"

# unfsd discovery outside PATH (/usr/sbin) via a stub
stub=/usr/local/sbin/unfsd; created=0
if [[ ! -e /usr/sbin/unfsd && ! -e $stub ]]; then
  install -D -m 0755 /dev/stdin "$stub" <<<$'#!/bin/sh\nexit 0'; created=1
fi
out="$(WSLC="$fake" env PATH=/usr/bin:/bin wslc _check 2>&1 || true)"
grep -q 'userspace NFS server' <<<"$out" && pass "_check finds unfsd off PATH" || fail "_check unfsd discovery: $out"
[[ $created == 1 ]] && rm -f "$stub"

check "build helper present" test -x /usr/bin/wslc-build-unfsd
# Regression: the installed package itself Recommends unfs3, which must not make
# the helper believe unfs3 is installable. Expect "apt" only if a candidate exists.
want=source; [[ -n "$(apt-cache policy unfs3 | awk '/Candidate:/ && $2!="(none)"{print $2}')" ]] && want=apt
[[ "$(WSLC_BUILD_UNFSD_DRY_RUN=1 wslc-build-unfsd)" == "$want" ]] && pass "build helper picks $want path" || fail "build helper path (wanted $want)"

# Remove / purge cleanly
apt-get remove -y wslc-remote >/dev/null
[[ ! -e /usr/bin/wslc && ! -e /usr/bin/container ]] && pass "remove deletes files" || fail "remove left files"
dpkg -P wslc-remote >/dev/null 2>&1; pass "purge"
echo "all tests passed"
