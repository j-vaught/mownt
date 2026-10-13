# Configuration and commands

`mownt` reads a private mount table and optional automation settings. Both are parsed as data. By default they live in `${XDG_CONFIG_HOME:-$HOME/.config}/mownt`. `--config FILE` selects another mount table and uses the `automation.conf` beside that file.

## Mount table

Each nonblank, noncomment line of `mounts.tsv` contains exactly six fields separated by literal tabs. Comment lines start with `#`. A row describes one filesystem.

| Field | Meaning | Example |
| --- | --- | --- |
| `group` | `theia`, `delta`, or `perception`. | `theia` |
| `label` | Unique mount name. | `theia-home` |
| `ssh_aliases` | SSH alias or comma-separated aliases in priority order. | `relay-a,relay-b` |
| `remote_path` | Directory exposed through SFTP. | `/home/YOUR_ACCOUNT` |
| `local_path` | Dedicated mountpoint beneath your local home. | `~/theia-home` |
| `mode` | `rw` for normal access or `ro` for read-only access. | `rw` |

The template uses read/write mode and the original local folder names. Replace account paths and SSH aliases with your private values, then remove unused rows. Put usernames, ports, keys, and jump-host settings in `~/.ssh/config`.

Labels use letters, digits, underscores, and hyphens, beginning with a letter or digit. SSH aliases additionally allow dots. Paths use a restricted ASCII set of letters, digits, underscores, hyphens, dots, and slashes. Remote paths may be absolute or home-relative, including `~/`. The command normalizes remote `~/suffix` to the SFTP home-relative `suffix`. Local paths must be strictly beneath your home directory, written as an absolute path or with `~/`. Whitespace, executable expressions, traversal through `..`, and symlink components are rejected.

For relays, a home-relative share path resolves beneath each account's home. Their shell and SFTP views must agree. This supports different absolute home directories across hosts. Mountpoints must be unique, unnested, user-owned, and empty before the first mount.

## Automation settings

`automation.conf` contains one literal uppercase `KEY=value` per line. It is not a shell script. Use no shell quotes, command substitutions, or environment expansions. Local path settings accept `~/` as a shorthand for your home directory. The example file provides these defaults.

```ini
SSH_MASTER=yes
TAILSCALE=auto
DELTA_LOGIN=~/.ssh/delta-login
AUTO_PROVISION=yes
AUTO_FORCE=yes
DIRECT_FALLBACK=yes
SMB_REMOTE=perception
SMB_SHARE=share
RCLONE_CONFIG=~/.config/rclone/rclone.conf
```

| Setting | Behavior |
| --- | --- |
| `SSH_MASTER=yes` | Establish and reuse a shared authenticated connection for each host. |
| `TAILSCALE=auto` | Start an installed Tailscale connection when needed. `off` leaves it alone. |
| `DELTA_LOGIN=~/.ssh/delta-login` | Use this trusted executable for Delta login when available. `none` disables the helper. |
| `AUTO_PROVISION=yes` | Install or repair the managed relay tooling and synchronize the selected SMB configuration. |
| `AUTO_FORCE=yes` | Escalate normal client unmount failure to force or lazy detach for the expected local mount. |
| `DIRECT_FALLBACK=yes` | Try local rclone access when no relay is usable. |
| `SMB_REMOTE=perception` | Select the named local rclone SMB configuration block. |
| `SMB_SHARE=share` | Select the share inside that SMB remote. |
| `RCLONE_CONFIG=~/.config/rclone/rclone.conf` | Read and update the selected credential in this private file. |

The boolean settings accept `yes` or `no`. Leave the defaults for the complete one-command workflow. Change them when your environment needs different behavior. Secrets belong in the private rclone configuration or the local credential mechanism used by your trusted login helper, rather than in these settings.

`DELTA_LOGIN` is executable local code and must be trusted. It receives the SSH alias and must establish the connection using the configured SSH control socket. A helper that retrieves a password from a local operating-system credential store can keep that existing convenience. Without an executable helper, SSH handles login interactively.

## Private paths and permissions

The mount table and settings must be beneath your home directory, owned by you, and mode `600`. Their immediate parent directory must be mode `700`. Path components from your home directory must not be symlinked or writable by other users. The same principle protects configured helpers, rclone configuration, and SSH control sockets. Keep live configuration outside the repository.

## Commands

With no action, `mownt` runs `up`. With no group selector, it operates on every configured group. Selectors can be combined.

| Command | Result |
| --- | --- |
| `mownt` or `mownt up` | Connect, repair required services, and mount configured drives. |
| `mownt -t` or `mownt --theia` | Select `theia`. |
| `mownt -d` or `mownt --delta` | Select `delta`. |
| `mownt -p` or `mownt --perception` | Select the share relay group. |
| `mownt -a` or `mownt --all` | Select all groups. |
| `mownt down` or `mownt -x` | Unmount selected drives, using configured recovery behavior. |
| `mownt status` or `mownt -s` | Report local mount state and responsiveness. |
| `mownt doctor` | Check local configuration and dependencies without network operations. |
| `mownt setup` or `mownt -setup` | Provision and synchronize the configured share relays. |
| `mownt passwd` or `mownt -pw` | Update the saved SMB credential and synchronize and refresh relays. |
| `mownt --dry-run` | Preview the selected operation without making changes. |
| `mownt down --force -p` | Explicitly request force or detach for selected share mounts. |
| `mownt --config "$HOME/.config/mownt-alt/mounts.tsv"` | Use another private configuration. |
| `mownt --help` | Show accepted arguments. |
| `mownt --version` | Print the installed version. |

The longer single-dash legacy selectors remain available. `passwd` updates saved client credentials; the account's actual password is changed through its owning service.

## Daily lifecycle

For direct SSHFS drives, `mownt` opens or reuses each host's SSH master before mounting its directories. The shared connection lets a host's mounts reuse the password or multifactor approval until that connection expires. The configured login helper can establish the Delta master using an existing local credential workflow.

For the share, the command starts configured network access, tries relay aliases in order, installs missing rclone from a pinned official artifact with a matching SHA256 checksum, synchronizes only the selected SMB block, and runs the managed backing-share helper. A failed candidate leads to the next alias. If none succeeds and direct fallback is enabled, local rclone attempts the same share.

A live expected mount is reused. A stale expected local mount is unmounted and recreated, with client force escalation controlled by `AUTO_FORCE`. Relay backing-share recovery separately attempts normal unmounting and then lazy detachment when necessary. A foreign mount or a nonempty unmounted directory is refused. Force can interrupt open work; on Linux, lazy detachment does not prove that the filesystem process has exited or pending writes have completed.

`status` checks local responsiveness. It does not prove remote write durability or that a backing share remains mounted after its initial check. Exit status zero indicates success; failed operations and invalid configuration return a nonzero result with a diagnostic.
