# Debian/Ubuntu package

Builds `wslc-remote_<version>_all.deb`, which installs `/usr/bin/wslc`, the
`/usr/bin/container` alias and `/usr/bin/wslc-build-unfsd`.

```sh
packaging/deb/build.sh            # -> packaging/deb/dist/*.deb
sudo apt install ./packaging/deb/dist/wslc-remote_*.deb
```

`unfsd` (UNFS3) is a *Recommends*: it is pulled in where the distro packages `unfs3`.
Where it does not (e.g. Ubuntu 24.04), run `sudo wslc-build-unfsd` to build the
official release, with the WSL IPv4 socket patch, into `/usr/local/sbin`.
`wslc` finds it in `/usr/local/sbin` or `/usr/sbin` even when not on `PATH`.

## Testing

```sh
packaging/deb/tests/test.sh                       # as non-root: build + static checks only
docker run --rm -v "$PWD":/src -w /src ubuntu:24.04 \
  bash -c 'apt-get update -qq && apt-get install -y -qq lintian shellcheck && packaging/deb/tests/test.sh'
```

As root it also installs the package, runs `wslc`/`container` against a fake
`wslc.exe`, checks `unfsd` discovery off `PATH`, and removes/purges it.

## Releases

`.github/workflows/deb.yml` runs the tests on every pull request. On a push to `main` (a merged
PR) it also builds `wslc-remote_<VERSION>+git<date>.<sha>_all.deb` and publishes it as a GitHub
release. Bump the base version in `packaging/deb/VERSION` for a new release series.
