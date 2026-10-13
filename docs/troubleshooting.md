# Troubleshooting

Start with `type -a mownt`, `mownt doctor`, `mownt --dry-run`, and `mownt status`. This establishes which executable is running, whether the private configuration is valid, and what operation is planned. Do not post raw configuration, command previews, SSH logs, or mount listings publicly without removing account names, addresses, and sensitive paths.

## The command is missing or an old version runs

Confirm that the installer completed and that its prefix's `bin` directory is on `PATH`. Open a new shell after changing the startup file. An alias, shell function, or earlier executable may take precedence over `~/.local/bin/mownt`; `type -a mownt` reveals that ordering.

## Configuration is refused

The config file needs exactly six literal tab-separated fields per data row, a unique label and mountpoint, valid groups and modes, and permitted paths. Use `cat -t` locally to make tabs visible as `^I`. Check the path selected by `--config` or `XDG_CONFIG_HOME`, then correct its owner and permissions. The immediate parent must be owned by you with mode `700` and the file with mode `600`. Symlinked configuration and mountpoint components are refused.

```sh
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mownt"
ls -ld "$config_dir" "$config_dir/mounts.tsv"
chmod 700 "$config_dir"
chmod 600 "$config_dir/mounts.tsv"
mownt doctor
```

Do not use `sudo mownt` to bypass a permission error. Create a normal-user configuration and mountpoint instead. Whitespace in local home or mount paths is outside the supported configuration format.

## Host-key checking fails

An unknown key requires the verification procedure in [setup](setup.md). A changed key requires independent confirmation of the server's current fingerprint and the reason for the change. A host-key warning can indicate interception or the wrong destination. Do not disable checking, blindly remove `known_hosts`, or accept a replacement to make the error disappear. After an administrator confirms a legitimate replacement, update only the affected entry using the institution's approved process.

## Authentication repeats or fails

Test the same alias with `ssh -o ControlPath=none -o StrictHostKeyChecking=yes ALIAS` and test `sftp` separately. Recheck your account, key enrollment, agent, network access, and the server's multifactor policy. `mownt` disables connection sharing, so an existing SSH master does not bypass authentication. Multiple mounts may prompt separately. An SFTP-only account can succeed through SSHFS even if it does not permit an interactive shell.

Inspect `ssh -G ALIAS` locally to see effective SSH settings. Your SSH configuration is trusted executable configuration and may include a proxy command or a `Match exec` condition. Review included files and remove unwanted local behavior. Do not share the full output publicly without redaction.

## SSH works but SSHFS fails

Confirm `sshfs --version` works and that the FUSE runtime is installed and available to your user. On macOS, complete the runtime's operating-system approval and restart steps. On Linux, a container, unavailable `/dev/fuse`, or restricted user-mount policy may require administrator assistance. Confirm that the remote server permits SFTP and that your configured directory exists inside its SFTP view.

The command uses SSHFS `default_permissions` and `idmap=user`. These apply local permission checks and map the authenticated remote user's identifiers. Supplementary shared-group identifiers can still differ between machines, so an operation may work through SFTP but fail on a locally mounted shared directory. Ask the server administrator to resolve the permission model rather than disabling local checks or granting broad access.

## A mountpoint is nonempty

`mownt` refuses to hide local files under a new mount. Confirm the directory is unmounted, inspect its contents, and move any real local data to a separate safe location. Use a fresh empty dedicated directory when possible. Do not delete files just to satisfy this check, and never run recursive removal against a mountpoint.

## A mount is stale or busy

Save and close files, stop jobs accessing the mount, and move terminal working directories outside it. Check the network and remote server. Then run a normal unmount of the affected group and remount deliberately.

```sh
cd "$HOME"
mownt down -d
mownt -d
```

If ordinary unmounting still fails, investigate which local applications hold files open using your operating system's tools. `lsof` may help with a busy mount but can itself wait on a broken filesystem. Force is an explicit last step after assessing pending writes.

```sh
mownt down --force -d
```

Forced unmounting can interrupt open files and pending writes. On Linux it requests lazy detachment, which does not establish that the filesystem process exited or its writes finished. Restore connectivity and verify important files through a separate session before resuming work.

## A relay looks empty or the wrong relay is selected

Log into the selected relay and confirm that its backing share is mounted at the configured remote path, then inspect expected contents. A relative path is resolved beneath that relay account's home directory, and the shell and SFTP views must agree. The connection-time `mountpoint` check rejects a missing backing mount but cannot prevent it from disappearing during the session. Stop laptop clients before restarting or unmounting a relay share. Verify the account and backing configuration independently on every failover host. See [relay setup](relay.md) before enabling writes.

The alias list is mount-time failover, not replication. An established mount does not switch an open file to another relay. If every relay fails, investigate the individual authentication, network, backing mount, and SFTP errors. The command does not silently switch to direct SMB or NFS access.
