# Optional relay setup

A relay makes a network-restricted share visible through a server that you can reach over SSH. `mownt` mounts that server's prepared directory through SFTP. The relay is therefore trusted with the account's data and any credentials it needs for the upstream share. Obtain the server owner's approval and use an account limited to the necessary share.

## Establish network access

Use the network route approved by the server administrator. For Tailscale, install the official client using the [macOS guide](https://tailscale.com/docs/install/mac) or the [Linux package instructions](https://tailscale.com/docs/install/linux). Enroll the device yourself and restrict access through the tailnet's access policy. `mownt` does not start, authenticate, or change Tailscale.

Regular SSH can run over a Tailscale address without enabling Tailscale's separate SSH server feature. Configure your alias's `HostName` to the approved address or DNS name and verify its SSH host key as usual. Follow the [SSH-over-Tailscale guide](https://tailscale.com/docs/reference/ssh-over-tailscale) for that arrangement. Enabling Tailscale SSH instead requires its own server and policy setup; do not enable it solely to use this tool.

Relay checks run with SSH `BatchMode=yes` and connection sharing disabled. Configure approved noninteractive authentication through an enrolled key, agent, or certificate. A password prompt, multifactor prompt, or an already-open SSH master cannot satisfy this check. Do not weaken an institution's authentication policy to accommodate a relay; use an approved endpoint instead.

For the passphrase-protected key in [setup](setup.md), load it into your local session's SSH agent before mounting. If no agent is available, start the agent provided by your operating system or desktop session. Enter the passphrase at its prompt, then verify a noninteractive connection to every relay.

```sh
ssh-add "$HOME/.ssh/id_ed25519_mownt"
ssh-add -l
ssh -o ControlPath=none -o BatchMode=yes -o StrictHostKeyChecking=yes relay-a true
ssh -o ControlPath=none -o BatchMode=yes -o StrictHostKeyChecking=yes relay-b true
```

## Prepare the backing share on each relay

The following optional example uses rclone on a Linux relay. Install its approved package and FUSE runtime through the server's administrator or the [official installation instructions](https://rclone.org/install/). Verify downloaded artifacts using that release's published verification procedure. The example assumes the relay can already reach the SMB server and that the administrator permits user-level FUSE mounts.

Log into the relay, prepare private directories, and configure a remote named `research-share` interactively. Choose the SMB backend and enter the approved hostname, account, domain, and authentication details. The [SMB backend reference](https://rclone.org/smb/) also describes Kerberos configuration where your institution requires it.

```sh
umask 077
mkdir -p "$HOME/.config/rclone" "$HOME/.cache/rclone-research" "$HOME/mnt/share"
chmod 700 "$HOME/.config/rclone" "$HOME/.cache/rclone-research" "$HOME/mnt/share"
rclone config
rclone config file
```

Confirm the reported configuration location is private and apply mode `600` to that actual file. With the default path, use the following command.

```sh
chmod 600 "$HOME/.config/rclone/rclone.conf"
rclone lsd research-share:
```

Keep the file out of this repository. A password produced by `rclone obscure` is reversible obfuscation, not protection against someone who can read the file. The [obscure reference](https://rclone.org/commands/rclone_obscure/) explains this distinction. Rclone supports configuration encryption; follow its [configuration documentation](https://rclone.org/docs/#configuration-encryption) if required, and provide the encryption password interactively. Do not put either kind of password on a command line or copy a credential block between relays automatically.

For the first test, replace `SHARE_NAME` with the approved share name and keep the mount read-only. Run in a dedicated terminal so errors remain visible.

```sh
rclone mount research-share:SHARE_NAME "$HOME/mnt/share" \
    --read-only \
    --cache-dir "$HOME/.cache/rclone-research" \
    --vfs-cache-mode full \
    --vfs-cache-max-size 20G
```

Use a second relay session to verify that the path is actually a mounted filesystem and that expected contents are present.

```sh
mountpoint -q "$HOME/mnt/share"
ls "$HOME/mnt/share"
```

Point the laptop's `perception` row at `~/mnt/share`, as in the template, and use mode `ro`. This group requires the relay's `mountpoint` utility, because the command checks that path before mounting it. The relative suffix resolves beneath each relay account's own home, allowing different absolute home directories. Its shell and SFTP homes must agree. Prepare and verify each additional relay independently before adding it to the comma-separated alias list. Every relay must expose the same upstream directory at that corresponding path with equivalent permissions.

## Preserve the backing-mount boundary

Before selecting a `perception` relay, `mownt` checks that its resolved backing path is a mountpoint and rejects failures. If that backing mount disappears afterward, its underlying directory can still be exposed through an existing SSHFS connection. A healthy laptop mount therefore does not prove that the upstream share remains mounted. Before writing, verify the backing filesystem on the relay and its expected contents. Keep the local row read-only until that check succeeds. An administrator can provide a guarded SFTP service or another supervised arrangement that refuses access when the backing mount is absent.

For write access, the relay operator must deliberately remove `--read-only` and the laptop configuration must use `rw`. Protect the cache directory and its disk, because cached file contents may be sensitive. Rclone caches can exceed their configured size while files remain open, and writes may still be waiting for upload after an application closes a file. Its [mount and cache documentation](https://rclone.org/commands/rclone_mount/) describes durability, retry, and shutdown behavior.

Close client files, unmount the laptop normally, and verify pending uploads on the relay before shutting down the backing mount. Do not delete its cache to fix an upload problem. For unattended operation, ask the relay administrator to supervise the mount using the host's supported service manager, with private logs and credentials, upstream connectivity checks, and a shutdown process that preserves pending writes.
