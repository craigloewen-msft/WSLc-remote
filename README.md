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

## Requirements

- WSL with container support (provides `wslc.exe`)
- **WSL localhost forwarding** between the container runtime VM and your distro. Both
  `networkingMode=mirrored` and `networkingMode=virtioproxy` (`Consomme`) are supported.
  Run `wslc _check` to test the actual connection instead of relying on the configured
  mode name. After changing `%USERPROFILE%\.wslconfig`, run `wsl --shutdown`.
- bash 4+
- **`flock`** from `util-linux` — normally installed by default on supported WSL
  distros; used to coordinate concurrent share creation, recovery, teardown, and pruning.
- **`unfsd`** — the [UNFS3](https://github.com/unfs3/unfs3) userspace NFSv3 server. The
  installer gets it from the distro package where available, or builds the official release
  automatically on Debian/Ubuntu:

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

# stopped containers keep using their existing NFS-backed shares
wslc stop my-container
wslc start my-container        # restores the share first, then starts it
```

`wslc start` restores any tracked NFS shares used by the existing container before delegating
to the real WSLC start command. This allows a stopped container to recover after the WSL distro
or container runtime VM has stopped without recreating the container. Recovery validates the
saved `unfsd` process identity and export configuration before reusing a live NFS endpoint; an
occupied endpoint whose identity cannot be verified is rejected rather than mounted. Tracked
shares created by older versions are migrated in place when their running `unfsd` instance can
be independently verified. Recovery also performs a bounded, force-synchronized probe of an
existing NFS mount before reuse and verifies that its root fileid still matches the current source
directory inode. An unhealthy mount is remounted only when no running container is using that
volume. Existing-container start and run/create bind setup remain synchronized with mount repair
until the runtime has consumed or committed the validated backing volumes; attached sessions do
not retain that lifecycle lock afterward.

`wslc volume remove` / `wslc volume prune` also tear down the matching NFS share. All other
`volume` subcommands pass straight through.

wslc-remote adds exactly two commands of its own, both `_`-prefixed so they can never collide
with a current or future `wslc` subcommand: `wslc _check` and `wslc _help`.

## How it works

For each host bind mount, wslc-remote:

1. starts a `unfsd` NFSv3 server in your distro, exporting that directory on loopback only,
2. creates a `wslc` guest volume and NFS-mounts that server onto the volume's backing store
   inside the runtime VM,
3. rewrites your `-v /host/dir:/ctr` into `-v <volume>:/ctr` and execs the real `wslc`.

The container sees an ordinary bind mount. Traffic goes over NFS on `127.0.0.1` through WSL
localhost forwarding instead of virtiofs. Shares are reused across runs and torn down with their
volume.

## Configuration

| Variable | Default | |
|---|---|---|
| `WSLC` | `wslc.exe` on PATH, else `/mnt/c/Program Files/WSL/wslc.exe` | path to the real wslc CLI |
| `WSLC_REMOTE_UNFSD` | `unfsd` | path to the unfsd binary |
| `WSLC_REMOTE_BASE_PORT` | `12049` | first port in the range used for NFS servers |
| `WSLC_REMOTE_STATE` | `~/.local/state/wslc-remote` | share state, lifecycle locks, logs, exports |

The installer also takes `--dir DIR`, `--ref REF` and `--skip-deps`.

## Uninstall

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
