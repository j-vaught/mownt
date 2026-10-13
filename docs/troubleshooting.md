# Troubleshooting

Start with `type -a mownt`, `mownt doctor`, `mownt --dry-run`, and `mownt status`. These identify the executable, validate local files, preview the operation, and report mount health. Remove accounts, addresses, credentials, and sensitive paths before sharing diagnostic output.

## An old command runs

Check `type -a mownt` for an alias, function, or earlier executable. Put the selected installation prefix's `bin` directory on `PATH` and open a new shell. `mownt --version` identifies the installed release.

## Configuration is refused

The mount table requires six literal tab-separated fields per data row. Use `cat -t` locally to display tabs as `^I`. `automation.conf` uses literal `KEY=value` lines without shell quoting or expansion. Both files must be private and owned by you.

```sh
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mownt"
chmod 700 "$config_dir"
chmod 600 "$config_dir/mounts.tsv" "$config_dir/automation.conf"
mownt doctor
```

Configuration and mountpoint ancestors cannot be symlinked or writable by other users. Unsupported whitespace or path traversal is refused. Use normal dedicated mountpoint directories rather than running the command with administrative privileges.

## A host key is unknown or changed

Follow the initial verification procedure in [setup](setup.md). Obtain fingerprints through an independent trusted channel. For a changed key, confirm the server and reason for the change with its administrator before updating the affected entry. Do not disable checking or erase `known_hosts` to clear the error.

## Authentication repeats

`mownt` shares the authenticated connection for a host while its SSH master remains valid. A fresh or expired session still requires the server's password or multifactor approval. Use the same alias throughout the mount table and any login helper, and keep the configured control-socket directory private.

If a trusted `delta-login` helper is configured, confirm it is executable and creates the master's configured control socket. Without a helper, SSH prompts normally. A passphrase-protected key can be loaded into the local SSH agent with `ssh-add "$HOME/.ssh/id_ed25519_mownt"`.

Inspect `ssh -G ALIAS` locally to check effective host, user, and control settings. A proxy command or `Match exec` condition remains trusted SSH configuration. Do not post that full output publicly without redaction.

## SSH works but the filesystem does not

Confirm `sshfs --version` runs and that FUSE is available to your account. Complete macOS runtime approval and restart requirements. On Linux, a container or restricted `/dev/fuse` may need the host administrator's supported configuration. Verify the directory through `sftp ALIAS`; its view can differ from the login shell.

The SFTP server enforces the authenticated account's permissions, including access through remote project groups. SSHFS maps the account's identifiers with `idmap=user` and limits local access to the mounting user. The command omits `default_permissions` and `allow_other`, preserving remote group access without exposing the mount to other local users. See the [SSHFS permission guidance](https://github.com/libfuse/sshfs/blob/master/sshfs.rst).

## The share relay fails

Run `mownt setup` to repeat provisioning and credential synchronization, then `mownt -p`. Check the selected SMB remote and share names in `automation.conf`, the local private rclone configuration, relay SSH access, FUSE availability, and upstream network reachability. An installed Tailscale client must have been enrolled once before automatic startup can connect it.

A checksum failure stops a relay binary installation. Retry after checking the official release and the reviewed pin; do not bypass the check. If a host is unavailable, the next configured relay is tried. If all fail, direct fallback needs local rclone and a route to the SMB server. A home-relative relay path requires matching shell and SFTP home views.

After an institutional password change, run `mownt passwd` to update the saved credential and refresh reachable relays. Offline relays synchronize on a later run. This command changes saved clients rather than the actual server password.

## A mount is stale or busy

`mownt` automatically repairs stale expected mounts, first normally and then with configured force escalation. Close applications and leave mountpoint working directories before a planned unmount. A clean shutdown is still best for ongoing writes.

```sh
cd "$HOME"
mownt down -d
mownt -d
```

A foreign mount is refused rather than recovered. Inspect its source and unmount it through the application that owns it. An unmounted nonempty directory is also refused; preserve its local files in another location or use a fresh empty mountpoint.

Force can interrupt writes. Linux lazy detachment does not establish that the filesystem process exited or buffered data arrived. After an interrupted connection, verify important files through another session before resuming work. Preserve relay caches while uploads remain pending.

## Recovery reaches an empty directory

A relay backing share is checked before use, but can disappear during a session. Stop clients, let `mownt setup` repair the relay, and run `mownt -p` again. Inspect expected content before restarting interrupted jobs. Ordered failover chooses a new mount; it does not migrate open files or replicate data between servers.
