# Migrate an existing installation

Version 1.1 restores the original daily workflow. Configure a new computer once, then use the familiar `mownt`, group selectors, status, unmount, setup, and saved-password update commands. SSH authentication is shared across each host's mounts, relays are prepared automatically, and stale mounts are recovered without a separate repair routine.

## Preserve your private setup

Keep a local backup of the existing command before installing over its path. Its server addresses and account paths belong outside this public repository.

```sh
umask 077
mkdir -p "$HOME/.local/share/mownt-backup"
chmod 700 "$HOME/.local/share/mownt-backup"
cp "$HOME/.local/bin/mownt" "$HOME/.local/share/mownt-backup/mownt-before-public-release"
chmod 600 "$HOME/.local/share/mownt-backup/mownt-before-public-release"
```

If your command is elsewhere, substitute its verified path. Finish pending work and unmount before replacing the executable. Use the data-only importer below or follow [setup](setup.md) to create the release's private configuration. Never source the old script to extract its settings.

For the original script layout, the importer reads its known literal settings and writes private release configuration. Run it before replacing the old command. The destination must be beneath your home directory and contain no existing configuration files.

```sh
./tools/import-legacy.sh "$HOME/.local/bin/mownt" "$HOME/.config/mownt"
./install.sh --force
mownt doctor
mownt
```

The importer does not execute the old script, contact servers, or copy credentials. It preserves recognized drive paths, SSH aliases, SMB remote and share names, and the local rclone configuration path. Inspect the resulting files before the first run. Unsupported script layouts are refused instead of guessed.

If you already created version 1.0 settings, import into a separate private directory and compare the result before deliberately replacing your active files.

```sh
./tools/import-legacy.sh "$HOME/.local/share/mownt-backup/mownt-before-public-release" "$HOME/.config/mownt-import"
```

## Map the original drives

The public template keeps the original local folder layout in read/write mode. Replace its remote paths and aliases with your own private values.

| Group | Typical label | Remote directory | Local mountpoint |
| --- | --- | --- | --- |
| `theia` | `theia-home` | Your account's home directory. | `~/theia-home` |
| `theia` | `theia-work` | Your work directory. | `~/theia-work` |
| `delta` | `delta-home` | Your cluster home directory. | `~/delta-home` |
| `delta` | `delta-scratch` | Your allocation's scratch directory. | `~/delta-scratch` |
| `delta` | `delta-projects` | Your allocation's project directory. | `~/delta-projects` |
| `perception` | `perception_wang` | The prepared share beneath each relay account's home. | `~/perception_wang` |

The share label is a local name. Keep your current name or change it in your private mount table. A home-relative relay path works across accounts with different absolute home directories when their shell and SFTP views agree.

## Keep the automation

Configure the share remote once through local `rclone config`. Select that remote and its share in `automation.conf`. `mownt setup` then installs missing relay tooling, synchronizes that selected credential block over SSH, and installs the managed helper. Ordinary `mownt` also repairs missing pieces as needed and tries relays in order.

If your existing cluster login uses a trusted executable such as `~/.ssh/delta-login`, retain that path in `DELTA_LOGIN`. It remains a local executable and receives the selected SSH alias. Keep its credential retrieval local, such as an operating-system credential store, rather than placing a password in this repository. Without a helper, SSH prompts normally and the authenticated master is reused for the host's directories.

Tailscale startup, direct share fallback, and automatic stale-mount recovery are available again. Their configuration is described in the [reference](configuration.md). The command retains strict host-key verification, so verify initial host fingerprints through the [setup procedure](setup.md) before the first automated connection.

The `passwd` action updates the saved SMB client credential and distributes it to configured relays. It does not change the underlying account password at the institution. Change that password through the approved account service first, then run `mownt passwd` to synchronize the clients.

## Upgrade from version 1.0

The six-column mount table remains the starting point. Add `automation.conf` and the local rclone share remote, restore your preferred local folder names, and select `rw` for normal write access. Version 1.0's manual relay preparation, repeated multifactor prompts, and explicit stale-repair routine are superseded by the automated workflow.

## Set up another computer

Clone the repository and follow [setup](setup.md). Enroll a fresh SSH key where allowed, verify host keys independently, recreate or privately transfer the mount settings, and enter the share credential through `rclone config`. Keep passwords and private keys outside version control. Once these local prerequisites are in place, run `mownt setup`, then use `mownt` for daily work.

When retiring a computer, revoke its obsolete device keys and VPN registration through their respective administrative services. Remove old local credentials through their owning applications when they are no longer needed.
