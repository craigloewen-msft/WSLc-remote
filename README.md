# wslc-remote

Use `wslc` inside a WSL distro.

The installer also provides `container` as an equivalent command:

```sh
container run --rm alpine echo hello
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/craigloewen-msft/WSLc-remote/main/install.sh | bash
```

Prefer to read it first (you should):

```sh
curl -fsSL https://raw.githubusercontent.com/craigloewen-msft/WSLc-remote/main/install.sh -o install.sh
less install.sh
bash install.sh
```

### Debian / Ubuntu package (apt)

On Debian and Ubuntu you can install a `.deb` instead of using the script. It puts `wslc`, the
`container` alias and `wslc-build-unfsd` in `/usr/bin` and is managed by `apt`/`dpkg`.

**From the wsl-transdebian repository.** The latest release package should be available from
the [wsl-transdebian](https://arkane-systems.github.io/wsl-transdebian/) apt repository. Add the
repository (see [its instructions](https://arkane-systems.github.io/wsl-transdebian/); in short):

```sh
sudo apt install lsb-release
sudo wget -O /etc/apt/trusted.gpg.d/wsl-transdebian.gpg https://arkane-systems.github.io/wsl-transdebian/apt/wsl-transdebian.gpg
sudo chmod a+r /etc/apt/trusted.gpg.d/wsl-transdebian.gpg
sudo tee /etc/apt/sources.list.d/wsl-transdebian.list > /dev/null << EOF
deb https://arkane-systems.github.io/wsl-transdebian/apt/ $(lsb_release -cs) main
deb-src https://arkane-systems.github.io/wsl-transdebian/apt/ $(lsb_release -cs) main
EOF
sudo apt update
sudo apt install wslc-remote
```

**From a release.** Every merge to `main` publishes the built `.deb` on this repository's
[Releases page](../../releases); download it and run `sudo apt install ./wslc-remote_*.deb`.

**Build it yourself.** If you would rather not trust a third-party repository (or a prebuilt
binary), build the package from a checkout (details in
[`packaging/deb/README.md`](packaging/deb/README.md)):

```sh
packaging/deb/build.sh
sudo apt install ./packaging/deb/dist/wslc-remote_*.deb
```

`unfsd` is pulled in automatically where your distro packages `unfs3`. Where it does not
(e.g. Ubuntu 24.04), run `sudo wslc-build-unfsd` to build the official release.
Remove with `sudo apt remove wslc-remote`.

## Requirements

- WSL with container support (provides `wslc.exe`)
- **A network path from the container runtime VM to your distro.** By default wslc-remote
  probes for one, so you don't need to pick a networking mode:
  1. `127.0.0.1` via WSL localhost forwarding, as in `networkingMode=mirrored` and
     `networkingMode=virtioproxy` (`Consomme`); if that fails,
  2. one of your distro's own IPv4 addresses (e.g. with bridged networking). The NFS server
     then listens on that address only and admits only the runtime VM's address. It is
     unauthenticated, so use this on networks you trust.

  The result is cached and re-checked when your address changes. Run `wslc _check` to see what
  was found; force a choice with `WSLC_REMOTE_ADDR`. After changing
  `%USERPROFILE%\.wslconfig`, run `wsl --shutdown`.
- bash 4+
- **`unfsd`** — the [UNFS3](https://github.com/unfs3/unfs3) userspace NFSv3 server. This is the
  only extra dependency. The installer gets it from the distro package where available, or
  builds the official release automatically on Debian/Ubuntu:

  | Distro | |
  |---|---|
  | Debian / Ubuntu | package when available; automatic source-build fallback |
  | openSUSE | `sudo zypper install unfs3` |
  | Arch | AUR only: `yay -S unfs3` |
  | Fedora / others | no package — build from source (below) |

  Building from source takes about a minute:

  ```sh
  git clone https://github.com/unfs3/unfs3
  cd unfs3
  ./bootstrap && ./configure && make && sudo make install
  ```

  Already have a binary? `export WSLC_REMOTE_UNFSD=/path/to/unfsd`.

## Usage

Anything you'd run with `wslc`:

```sh
# host bind mounts are transparently served over NFS
wslc run -v $(pwd):/work -w /work --rm debian:trixie-slim bash

# read-only binds stay read-only (the NFS export is read-only too)
wslc run -v $(pwd):/src:ro -v /home/me/data:/data --rm alpine sh

# --mount works as well
wslc run --mount type=bind,source=$(pwd),target=/work --rm alpine sh

# everything else is forwarded straight to the real wslc
wslc images
wslc inspect my-container
```

`wslc volume remove` / `wslc volume prune` also tear down the matching NFS share. All other
`volume` subcommands pass straight through.

wslc-remote adds exactly two commands of its own, both `_`-prefixed so they can never collide
with a current or future `wslc` subcommand: `wslc _check` and `wslc _help`.

## How it works

For each host bind mount, wslc-remote:

1. starts a `unfsd` NFSv3 server in your distro, exporting that directory to the runtime VM only
   (on loopback, or the address found by the network probe),
2. creates a `wslc` guest volume and NFS-mounts that server onto the volume's backing store
   inside the runtime VM,
3. rewrites your `-v /host/dir:/ctr` into `-v <volume>:/ctr` and execs the real `wslc`.

The container sees an ordinary bind mount. Traffic goes over NFS on `127.0.0.1` through WSL
localhost forwarding (or your distro's address, if loopback is unreachable) instead of virtiofs. Shares are reused across runs and torn down with their
volume.

## Configuration

| Variable | Default | |
|---|---|---|
| `WSLC` | `wslc.exe` on PATH, else `/mnt/c/Program Files/WSL/wslc.exe` | path to the real wslc CLI |
| `WSLC_REMOTE_UNFSD` | `unfsd` | path to the unfsd binary |
| `WSLC_REMOTE_ADDR` | `auto` | address the runtime VM uses to reach the NFS server: `auto` (loopback, else a reachable address of this distro) or an IP |
| `WSLC_REMOTE_CLIENT` | detected | client address the NFS export admits (only with a non-loopback `WSLC_REMOTE_ADDR`) |
| `WSLC_REMOTE_BASE_PORT` | `12049` | first port in the range used for NFS servers |
| `WSLC_REMOTE_STATE` | `~/.local/state/wslc-remote` | share state, logs, exports |

The installer also takes `--dir DIR`, `--ref REF` and `--skip-deps`.

## Uninstall

Installed the `.deb`? `sudo apt remove wslc-remote`. Installed with the script:

```sh
wslc volume prune           # tear down any remaining NFS shares first
rm -f ~/.local/bin/wslc ~/.local/bin/container ~/.local/bin/unfsd
rm -rf ~/.local/state/wslc-remote
```

`unfsd` was installed separately — remove it with your package manager if you don't want it.

## Support

Although I do work on the WSL team, this is being submitted as a community project from me personally (Craig Loewen) not as a representative of the WSL team. So this project will have community level support. Please treat it as you would any other open source community project. 

## License

MIT. See [LICENSE](LICENSE).
