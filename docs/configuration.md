# Configuration and commands

`mownt` reads a data file rather than executing a shell configuration. By default it uses `${XDG_CONFIG_HOME:-$HOME/.config}/mownt/mounts.tsv`. An explicit `--config FILE` selects another file with the same format and permission requirements.

## File format

Each nonblank, noncomment line contains exactly six fields separated by literal tabs. Comment lines start with `#`. A row describes one mountpoint.

| Field | Meaning | Example |
| --- | --- | --- |
| `group` | Selection group, `theia`, `delta`, or `perception`. | `theia` |
| `label` | Unique human-readable mount name. | `theia-home` |
| `ssh_aliases` | SSH alias or comma-separated aliases in priority order. | `relay-a,relay-b` |
| `remote_path` | Directory exposed through SFTP on each listed host. | `/home/YOUR_ACCOUNT` |
| `local_path` | Dedicated mountpoint beneath your local home directory. | `~/mnt/theia-home` |
| `mode` | `ro` for read-only, or `rw` for read/write. | `ro` |

The following shell command writes a single example row with actual tabs into a new private file. Replace its values before use and preserve any existing configuration.

```sh
umask 077
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mownt"
mkdir -p "$config_dir"
chmod 700 "$config_dir"
test ! -e "$config_dir/mounts.tsv" && printf 'theia\ttheia-home\ttheia\t/home/YOUR_ACCOUNT\t~/mnt/theia-home\tro\n' > "$config_dir/mounts.tsv"
chmod 600 "$config_dir/mounts.tsv"
```

Labels use letters, digits, underscores, and hyphens, beginning with a letter or digit. SSH aliases additionally allow dots. Put usernames, hostnames, ports, keys, and jump-host settings in your private `~/.ssh/config`. Do not put `user@host`, SSH flags, or shell commands in the alias field.

Paths accept a restricted ASCII set of letters, digits, underscores, hyphens, dots, and slashes. A remote path may be absolute, relative to the remote home, or begin with `~/`. The command normalizes remote `~/suffix` to the SFTP home-relative `suffix`. A local path must be an absolute path strictly beneath your home directory or begin with `~/`. Whitespace, shell expansions, traversal through `..`, and symlink components are rejected. Use uncomplicated dedicated mount directories when your normal directory names contain spaces. Relative remote paths are resolved by the SFTP server, whose view may differ from a login shell.

For `perception`, the backing-mount check resolves a relative remote path beneath each relay account's shell home directory. Its SFTP home must refer to that same location. This lets `~/mnt/share` work when relay accounts have different absolute home paths. If a server's shell and SFTP views differ, use a verified absolute path that works in both, or ask the administrator for an appropriate endpoint.

The file must be beneath your home directory and owned by your current user with mode `600`. Its immediate parent directory must be owned by your current user with mode `700`. Path components from your home directory must not be symlinked or writable by other users. These rules also apply when selecting a configuration with `--config` or `XDG_CONFIG_HOME`. An empty existing mountpoint must belong to you. Do not share mountpoints between rows or nest one configured mountpoint inside another. Store credentials elsewhere, and keep this file outside your repository even though it contains no passwords.

## Selection and actions

With no action, `mownt` runs `up`. With no group selector, it operates on every configured group. Selectors can be combined. Each group contains only the rows present in your file.

| Command | Result |
| --- | --- |
| `mownt` or `mownt up` | Mount configured directories. |
| `mownt down` | Normally unmount configured directories. |
| `mownt status` | Report local mount state and responsiveness. |
| `mownt doctor` | Validate local configuration and dependencies without a network connection. |
| `mownt -t` or `mownt --theia` | Select `theia`. |
| `mownt -d` or `mownt --delta` | Select `delta`. |
| `mownt -p` or `mownt --perception` | Select `perception`. |
| `mownt -a` or `mownt --all` | Select all groups. |
| `mownt --config "$HOME/.config/mownt-alt/mounts.tsv"` | Use a specific private configuration file. |
| `mownt --dry-run` | Print planned arguments without creating directories or mounts. |
| `mownt down --force -p` | Explicitly request forced unmounting or lazy detachment of `perception`. |
| `mownt --help` | Show accepted options. |

The single-dash legacy selectors `-theia`, `-delta`, `-perception`, `-all`, `-down`, and `-status` remain available. Legacy `-setup` and password-update options return an error directing you to manual administration. The [migration guide](migration.md) explains the changes.

## Mount behavior

For a new mount, aliases are tried in their configured order. A successful mount ends the attempt for that row. Each `perception` candidate must first pass a fixed remote `mountpoint` check over noninteractive SSH, requiring approved key, agent, or certificate authentication and the relay's Linux `mountpoint` utility. Failover establishes a fresh mount; it does not migrate open files or guarantee that two relays contain identical data. Confirm that every listed relay exposes the same directory and access policy.

The command requires trusted host keys and disables SSH connection sharing and forwarding for its connections. It does not accept arbitrary extra SSHFS options. SSH configuration remains a trusted local input, so inspect aliases and included files before using unfamiliar configuration.

An existing live mount is left in place. A mounted but unresponsive path is reported as stale and requires an explicit unmount before mounting again. An unmounted nonempty directory is refused so that local files are not hidden. Normal unmounting may fail while applications use the filesystem. Close those applications and retry before considering force. On Linux, force uses lazy detachment. A detached path does not establish that the filesystem process has exited or pending data has been flushed.

`status` reports local filesystem responsiveness. It cannot establish that the remote data is current, that cached writes are durable, or that a second filesystem behind a relay remains mounted. Exit status zero indicates command success. Failed operations and stale status produce a nonzero result. Invalid arguments and removed legacy actions also fail. Use the command's diagnostic text to identify the cause.
