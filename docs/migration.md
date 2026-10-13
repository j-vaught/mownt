# Migrate an existing personal installation

The public release replaces machine-specific settings with a private mount table and explicit setup. Your current command remains in place until you install over its path. Keep a local backup before making that change, and keep its private contents outside this public repository.

```sh
umask 077
mkdir -p "$HOME/.local/share/mownt-backup"
chmod 700 "$HOME/.local/share/mownt-backup"
cp "$HOME/.local/bin/mownt" "$HOME/.local/share/mownt-backup/mownt-before-public-release"
chmod 600 "$HOME/.local/share/mownt-backup/mownt-before-public-release"
```

If your existing command is elsewhere, substitute its verified path. Finish pending work and unmount using the existing command before installing the release. Follow [setup](setup.md) for the new machine or the new configuration. Do not import or source the old script.

## Map your drives

Copy the meaning of your old settings into the template, with your own accounts and paths. The following mapping preserves the original group layout while leaving institution-specific values private.

| Group | Typical label | Remote directory to establish through SFTP | Local mountpoint |
| --- | --- | --- | --- |
| `theia` | `theia-home` | Your account's home directory. | `~/mnt/theia-home` |
| `theia` | `theia-work` | Your work directory. | `~/mnt/theia-work` |
| `delta` | `delta-home` | Your cluster home directory. | `~/mnt/delta-home` |
| `delta` | `delta-scratch` | Your allocation's scratch directory. | `~/mnt/delta-scratch` |
| `delta` | `delta-projects` | Your allocation's project directory. | `~/mnt/delta-projects` |
| `perception` | `perception-share` | The same prepared share, for example `~/mnt/share` relative to each relay account's home. | `~/mnt/perception-share` |

You can retain an existing local mountpoint name by setting `local_path` accordingly, provided it passes validation and is empty while unmounted. Configure every selected relay alias locally and verify every host key. Keep `ro` until you have verified the correct contents and relay backing mount.

## Changed behavior

The usual group selectors, default mount-all action, status checks, and unmount action remain. The public release uses strict host-key checking rather than accepting first-seen keys automatically. It does not reuse an SSH master or invoke a password-filling login helper, so multifactor authentication may be requested for each mount.

Provisioning and password automation have moved out of the command. The former setup flow installed remote tools and copied a credential-bearing configuration to multiple servers. Configure each relay independently using [relay setup](relay.md). The old password action changed stored client credentials; it did not change the actual account password on the SMB server. Rotate the account password through the institution's approved service, then update each authorized client privately.

The public release does not enable a VPN, automatically mount a relay's backing share, or perform the former direct SMB/NFS fallback. Establish network access yourself, prepare the relay, and use the configured SSHFS path. It also avoids broad process termination and automatic force-unmount recovery. Explicit `down --force` remains available for a stuck local mount after you assess pending work.

## Move to another computer

Clone this repository and follow setup again. Generate a new private key where allowed and enroll the new computer under the server's policy. Recreate your mount table locally or transfer it through an authenticated private channel, then fix its ownership and modes on the destination. Obtain and verify server host keys through an independent trusted source. Transfer neither plaintext passwords nor private keys through this repository.

After verifying the new computer, revoke obsolete device keys and VPN registrations through their respective administrative services when you retire the old one. Keep the backup only as long as it is needed, because old scripts and client configuration can reveal infrastructure details.
