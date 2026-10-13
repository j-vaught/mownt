# mownt

One command for your remote drives.

`mownt` mounts groups of remote directories through SSHFS, checks their health, and unmounts them when you are done. It runs as your regular user on macOS and Linux, with a small private configuration file and your existing SSH aliases.

```sh
mownt                  # Mount every configured group.
mownt -t               # Mount theia.
mownt -d               # Mount delta.
mownt -p               # Mount perception, trying configured relays in order.
mownt status           # Inspect local mount state.
mownt down -d          # Unmount delta normally.
mownt doctor           # Check local configuration and dependencies.
mownt --dry-run -p     # Preview commands without creating mounts.
```

## A new computer

Install SSHFS and its FUSE runtime, then clone and inspect the repository before installing. The installer copies the command and an example configuration into `~/.local`. It leaves existing files alone unless `--force` is supplied.

```sh
git clone https://github.com/j-vaught/mownt.git
cd mownt
less bin/mownt install.sh
./install.sh --dry-run
./install.sh
export PATH="$HOME/.local/bin:$PATH"
```

Follow the [complete setup guide](docs/setup.md) to verify server identities, configure SSH aliases, create your private mount table, and perform a read-only first mount. The [configuration reference](docs/configuration.md) explains every field and command. The [migration guide](docs/migration.md) maps an existing personal installation to this release.

## Deliberate defaults

Server keys must already be trusted. The command enforces strict host-key checking, disables SSH connection sharing and forwarding, rejects executable configuration and unsafe paths, and refuses to cover a nonempty directory. Unmounting is normal by default. Forced unmounting requires an explicit `down --force` and can discard pending work.

Relay hosts must already expose their remote directories through SFTP. `mownt` does not provision servers, copy credentials, download dependencies, change passwords, start a VPN, or fall back to a different transport. See [relay setup](docs/relay.md), the [security model](SECURITY.md), and [troubleshooting](docs/troubleshooting.md).

## Project

Written by J.C. Vaught. Released under the [MIT license](LICENSE). Contributions follow [CONTRIBUTING.md](CONTRIBUTING.md). Release changes appear in [CHANGELOG.md](CHANGELOG.md).
