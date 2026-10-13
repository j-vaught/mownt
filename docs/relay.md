# Share relays and automatic setup

A relay reaches the SMB share from its own network and exposes it to your computer through SSHFS. Configure approved SSH aliases and the local SMB remote once. `mownt` then prepares the selected hosts, starts their share mount, and tries them in priority order.

## One-time inputs

Create the local rclone SMB remote through `rclone config`, then set its name and share in `automation.conf`. The default remote is `perception` and the default share placeholder is `share`. Replace the share placeholder with the real value. Set the `perception` row's aliases to your trusted relay hosts and its remote path to the directory to manage, such as `~/mnt/share`.

The relay accounts need SSH, SFTP, Bash, and working user-level FUSE mounts. The helper uses `curl`, `unzip`, `sha256sum`, `timeout`, `mountpoint`, and `fusermount3` or `fusermount`. These standard prerequisites can be installed once through the relay's supported package manager. For Debian or Ubuntu, the administrator's package command is `sudo apt install bash openssh-server fuse3 curl unzip coreutils util-linux`. Fedora uses `sudo dnf install bash openssh-server fuse3 curl unzip coreutils util-linux`.

After those operating-system prerequisites are available, setup runs as the remote account without system-package installation or remote administrative privileges. If FUSE is disabled by a managed server's policy, its administrator must enable an approved user-mount arrangement.

Configured relay aliases are trusted destinations for the selected SMB credential. The command sends that one named block over authenticated SSH and stores it in private relay files. This is the intended setup for mounting the same share from several hosts. Keep the alias list restricted to accounts and machines approved to hold that credential.

## Prepare and use the relays

With the private settings in place, run setup once to check the hosts immediately.

```sh
mownt setup
mownt -p
```

Ordinary `mownt` performs the same preparation when components are missing, so subsequent computers need no separate manual relay installation. Missing rclone is downloaded as a pinned official Linux release and checked against the expected SHA256 digest before installation. The pinned version and digests are part of the reviewed command, rather than taken from a moving latest-release URL. The upstream [downloads](https://rclone.org/downloads/) and [release verification guide](https://rclone.org/release_signing/) explain the official artifacts.

The managed helper creates and mounts the backing share, checks its responsiveness, and repairs its stale mount when necessary. The laptop verifies that backing path before opening SSHFS. If a relay cannot connect or mount the share, the next configured alias is tried. A home-relative path resolves beneath each remote account's own home, so those accounts may have different absolute home directories.

## Authentication and network access

SSH masters share the authenticated connection among provisioning, share checks, and filesystem mounts. A relay can therefore use the same password or multifactor session rather than requiring a separate login for each operation. Protect the configured control-socket directory with mode `700`. The [SSH control-socket documentation](https://man.openbsd.org/ssh_config#ControlPath) describes its role.

If the relays are reached through Tailscale, install and enroll its client once using the [macOS](https://tailscale.com/docs/install/mac) or [Linux](https://tailscale.com/docs/install/linux) instructions. `TAILSCALE=auto` lets `mownt` bring it up when necessary. Its account and network access policy remain your existing Tailscale configuration. Regular SSH over that route does not require enabling Tailscale's separate SSH server feature.

When every relay fails, `DIRECT_FALLBACK=yes` lets local rclone try the same SMB share directly. This succeeds when the computer has a route to the SMB server, such as the campus network or an approved VPN. Local rclone and the appropriate filesystem support must be installed once as described in [setup](setup.md).

The macOS fallback uses a loopback NFS server, whose access model trusts other local accounts. On a shared computer with untrusted users, set `DIRECT_FALLBACK=no` and retain the relay route. See the [security policy](../SECURITY.md) for that boundary.

## Update the share credential

After changing the actual account password through its owning institution, update the saved client credential.

```sh
mownt passwd
```

The command reads the replacement at hidden prompts, updates the selected local block, sends it to reachable configured relays, and refreshes the share mounts. An unreachable relay receives the current block on a later setup or mount run. Other rclone remote blocks are kept separate from this synchronization.

Rclone's obscured password representation is reversible and must be treated as a secret, as explained in the [obscure reference](https://rclone.org/commands/rclone_obscure/). Keep local and remote configuration private. The SMB server, the relay account, and the relay's administrator are within the trust boundary for that share.

## Service and cache behavior

The helper's cache supports normal file editing through rclone's virtual filesystem. Its cache at `~/.cache/mownt/rclone` stays private to the relay account. Recovery waits for an older rclone process using that cache to exit before restarting it. If the process remains busy, that relay attempt fails so another configured relay can be tried. Close client files before deliberately restarting a relay or changing its backing mount, and preserve its cache while uploads are pending. The [rclone mount documentation](https://rclone.org/commands/rclone_mount/) describes cache retries and shutdown behavior.

Automatic recovery restores availability; it does not prove that interrupted writes reached the server. A backing mount can also disappear after the laptop's initial check. After a network or server failure, verify important files through a separate session before resuming interrupted work. Use independent backups for important data.
