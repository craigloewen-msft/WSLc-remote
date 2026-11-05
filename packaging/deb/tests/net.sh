#!/usr/bin/env bash
# Exercise wslc's network-path detection with a fake unfsd and a fake wslc.exe
# whose "runtime VM" is this machine. Needs: python3, iproute2 (ip, ss).
# Run against the source tree, or against an installed package with WSLC_UNDER_TEST=/usr/bin/wslc.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wslc="${WSLC_UNDER_TEST:-$here/../../../wslc}"
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

for t in python3 ip ss; do command -v "$t" >/dev/null || { echo "skip net tests: $t missing"; exit 0; }; done
mapfile -t globals < <(ip -4 -o addr show scope global | awk '{split($4,a,"/"); print a[1]}')
[[ ${#globals[@]} -gt 0 ]] || { echo "skip net tests: no global IPv4 address"; exit 0; }
addr="${globals[0]}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# fake unfsd: listen on -l ADDR at -n PORT until killed
cat >"$tmp/unfsd" <<'PY'
#!/usr/bin/env python3
import socket, sys, time
a = sys.argv; addr = a[a.index('-l') + 1]; port = int(a[a.index('-n') + 1])
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((addr, port)); s.listen(8)
conns = []
while True:
    c, _ = s.accept(); conns.append(c)
PY
# fake wslc.exe: "system session run ARGS" runs ARGS here, but can hide loopback
cat >"$tmp/wslc.exe" <<'SH'
#!/bin/sh
[ "$1" = version ] && exit 0
if [ "$1 $2 $3" = "system session run" ]; then
  shift 3
  case "$*" in *"/dev/tcp/127.0.0.1/"*) [ -n "$FAKE_BLOCK_LOOPBACK" ] && exit 1 ;; esac
  exec "$@"
fi
exit 0
SH
# The real VM's sh understands /dev/tcp; dash here does not, so shadow it with bash.
mkdir "$tmp/bin"; ln -s "$(command -v bash)" "$tmp/bin/sh"
sed -i "s|^  exec \"\$@\"|  PATH=$tmp/bin:\$PATH exec \"\$@\"|" "$tmp/wslc.exe"
chmod +x "$tmp/unfsd" "$tmp/wslc.exe"

run() { # run <expr> in a fresh state dir with the wslc functions loaded
  WSLC="$tmp/wslc.exe" WSLC_REMOTE_UNFSD="$tmp/unfsd" WSLC_REMOTE_STATE="$tmp/state" \
    WSLC_REMOTE_BASE_PORT=23049 bash -c 'source "$1"; shift; eval "$@"' _ "$wslc" "$@"
}

rm -rf "$tmp/state"
out="$(FAKE_BLOCK_LOOPBACK='' run 'resolve_net; echo "$BIND_ADDR $CLIENT_ADDR"' 2>&1)"
[[ "$out" == "127.0.0.1 127.0.0.1" ]] && pass "loopback preferred when reachable" || fail "loopback case: $out"

rm -rf "$tmp/state"
out="$(FAKE_BLOCK_LOOPBACK=1 run 'resolve_net; echo "$BIND_ADDR $CLIENT_ADDR"' 2>&1)"
[[ "$out" == *"not loopback"* && "$out" == *"$addr $addr" ]] && pass "falls back to the distro address ($addr)" || fail "fallback case: $out"
grep -q "CACHED_BIND=$addr" "$tmp/state/net.env" && pass "result cached" || fail "cache not written"

out="$(FAKE_BLOCK_LOOPBACK=1 run 'resolve_net; echo "$BIND_ADDR $CLIENT_ADDR"' 2>&1)"
[[ "$out" == "$addr $addr" ]] && pass "cache reused without re-probing" || fail "cache reuse: $out"

printf 'CACHED_BIND=192.0.2.250\nCACHED_CLIENT=192.0.2.250\n' >"$tmp/state/net.env"
out="$(FAKE_BLOCK_LOOPBACK=1 run 'resolve_net; echo "$BIND_ADDR"' 2>&1)"
[[ "$out" == *"$addr" ]] && pass "stale cached address is re-detected" || fail "stale cache: $out"

rm -rf "$tmp/state"
out="$(FAKE_BLOCK_LOOPBACK=1 WSLC_REMOTE_ADDR="$addr" run 'resolve_net; echo "$BIND_ADDR $CLIENT_ADDR"' 2>&1)"
[[ "$out" == *"$addr $addr" ]] && pass "WSLC_REMOTE_ADDR override" || fail "override: $out"

rm -rf "$tmp/state"
out="$(FAKE_BLOCK_LOOPBACK=1 WSLC_REMOTE_ADDR="$addr" WSLC_REMOTE_CLIENT=10.9.8.7 run 'resolve_net; echo "$BIND_ADDR $CLIENT_ADDR"' 2>&1)"
[[ "$out" == *"$addr 10.9.8.7" ]] && pass "WSLC_REMOTE_CLIENT override" || fail "client override: $out"

# Nothing reachable at all -> clear failure, non-zero
rm -rf "$tmp/state"
cat >"$tmp/wslc-deaf.exe" <<'SH'
#!/bin/sh
[ "$1" = version ] && exit 0
[ "$1 $2 $3" = "system session run" ] && exit 1
exit 0
SH
chmod +x "$tmp/wslc-deaf.exe"
if out="$(WSLC="$tmp/wslc-deaf.exe" WSLC_REMOTE_UNFSD="$tmp/unfsd" WSLC_REMOTE_STATE="$tmp/state" WSLC_REMOTE_BASE_PORT=23049 \
     bash -c 'source "$1"; resolve_net' _ "$wslc" 2>&1)"; then fail "expected failure"; fi
[[ "$out" == *"cannot reach this distro"* ]] && pass "clear error when no address works" || fail "error text: $out"
# _check reports the address actually chosen, with what was probed, and refreshes the cache
rm -rf "$tmp/state"
out="$(FAKE_BLOCK_LOOPBACK=1 WSLC="$tmp/wslc.exe" WSLC_REMOTE_UNFSD="$tmp/unfsd" WSLC_REMOTE_STATE="$tmp/state" WSLC_REMOTE_BASE_PORT=23049 "$wslc" _check 2>&1 || true)"
[[ "$out" == *"can reach this distro on $addr (client $addr"* && "$out" == *"probed 127.0.0.1: unreachable"* ]] \
  && pass "_check reports the real address and probe results" || fail "_check output: $out"
printf 'CACHED_BIND=%s\nCACHED_CLIENT=%s\n' "$addr" "$addr" >"$tmp/state/net.env"
out="$(FAKE_BLOCK_LOOPBACK='' WSLC="$tmp/wslc.exe" WSLC_REMOTE_UNFSD="$tmp/unfsd" WSLC_REMOTE_STATE="$tmp/state" WSLC_REMOTE_BASE_PORT=23049 "$wslc" _check 2>&1 || true)"
grep -q 'CACHED_BIND=127.0.0.1' "$tmp/state/net.env" && pass "_check refreshes the cache" || fail "cache not refreshed: $out"
echo "net tests passed"
