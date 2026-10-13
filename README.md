# mownt

One command for your remote drives.

`mownt` brings your remote drives online, including the connections and relay services they depend on. Configure a new computer once, then run `mownt`. It reuses authenticated SSH sessions, provisions and repairs configured share relays, tries them in order, and checks the finished mounts.

```sh
mownt                  # Mount every configured group.
mownt -t               # Mount theia.
mownt -d               # Mount delta.
mownt -p               # Mount perception, trying configured relays in order.
mownt status           # Inspect local mount state.
mownt down -d          # Unmount delta.
mownt setup            # Provision and synchronize configured relays.
mownt passwd           # Update the saved share credential and synchronize relays.
mownt doctor           # Check local configuration and dependencies.
mownt --dry-run -p     # Preview commands without creating mounts.
```

## A new computer

Install SSHFS and its FUSE runtime, then clone and inspect the repository before installing. The installer copies the command, relay helper, and configuration templates into `~/.local`. It leaves existing files alone unless `--force` is supplied.

```sh
git clone https://github.com/j-vaught/mownt.git
cd mownt
less bin/mownt libexec/mownt-relay install.sh
./install.sh --dry-run
./install.sh
export PATH="$HOME/.local/bin:$PATH"
```

Follow the [complete setup guide](docs/setup.md) to configure SSH aliases, verify server identities, enter the share credential locally, and initialize your private settings. After that, `mownt` handles the routine connection, provisioning, failover, and mount work. The [configuration reference](docs/configuration.md) explains every field and command. The [migration guide](docs/migration.md) maps an existing personal installation to this release.

## Built for the daily command

SSH connection sharing lets several directories use one authenticated session, including one multifactor approval per host while the session remains valid. Configured relays receive only the selected share configuration over SSH. Missing relay tools are installed from a pinned, checksum-verified release, and the managed helper brings the backing share online. Tailscale startup, direct share fallback, and stale-mount recovery preserve the one-command workflow.

Strict host-key verification, private configuration and control sockets, constrained data fields, and mount-source checks protect that automation. Your configured relays are trusted with the share credential. Keep their aliases private and authorize only servers you control or are permitted to use. See [relay setup](docs/relay.md), the [security model](SECURITY.md), and [troubleshooting](docs/troubleshooting.md).

## Project

Written by J.C. Vaught. Released under the [MIT license](LICENSE). Contributions follow [CONTRIBUTING.md](CONTRIBUTING.md). Release changes appear in [CHANGELOG.md](CHANGELOG.md).
