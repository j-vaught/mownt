# Set up a new computer

Install the filesystem tools, configure your accounts once, and run `mownt setup`. After that, the daily command is `mownt`. It opens the required connections, reuses your authentication, prepares and repairs share relays, and mounts the drives.

## Install the local tools

On macOS, install the current macFUSE runtime and SSHFS package from the [official download page](https://macfuse.github.io/). They are separate installers. Complete the runtime's operating-system approval and restart steps. The [SSHFS installation guide](https://github.com/macfuse/macfuse/wiki/File-Systems-%E2%80%90-SSHFS) explains its signed installer certificate. macOS already includes Bash and SSH. If Git is missing, install Apple's command-line tools.

```sh
xcode-select --install
```

Install local rclone for share configuration, saved-password updates, and direct fallback. With an existing Homebrew installation, use `brew install rclone`; other supported methods appear in the [official rclone installation guide](https://rclone.org/install/).

On Debian or Ubuntu, install the distribution packages. Debian publishes the [SSHFS package and dependencies](https://packages.debian.org/stable/sshfs).

```sh
sudo apt update
sudo apt install bash git openssh-client sshfs rclone curl unzip
```

On Fedora, the SSHFS package is named [fuse-sshfs](https://packages.fedoraproject.org/pkgs/fuse-sshfs/fuse-sshfs/).

```sh
sudo dnf install bash git openssh-clients fuse-sshfs rclone curl unzip
```

Use your distribution's equivalents elsewhere. Run `mownt` as your regular user. Each Linux relay needs working user-level FUSE mounts, SFTP, and the normal shell utilities used by its managed helper. Missing rclone is installed automatically in that account; enabling FUSE on a restricted server remains an operating-system administrator task.

## Install mownt and its private settings

Clone the repository, inspect the command, and install it into `~/.local`.

```sh
git clone https://github.com/j-vaught/mownt.git
cd mownt
less bin/mownt libexec/mownt-relay install.sh
./install.sh
export PATH="$HOME/.local/bin:$PATH"
```

Add the `export PATH` line once to `~/.zshrc` for an interactive Zsh shell or to your shell's appropriate startup file. A custom prefix beneath your home directory is supported through `./install.sh --prefix "$HOME/tools/mownt"`; use its `bin` and `share/mownt` paths below.

Create the private configuration directory and copy both templates. These commands preserve existing live files.

```sh
umask 077
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mownt"
mkdir -p "$config_dir"
chmod 700 "$config_dir"
test ! -e "$config_dir/mounts.tsv" && cp "$HOME/.local/share/mownt/mounts.example.tsv" "$config_dir/mounts.tsv"
test ! -e "$config_dir/automation.conf" && cp "$HOME/.local/share/mownt/automation.example.conf" "$config_dir/automation.conf"
chmod 600 "$config_dir/mounts.tsv" "$config_dir/automation.conf"
"${EDITOR:-vi}" "$config_dir/mounts.tsv"
"${EDITOR:-vi}" "$config_dir/automation.conf"
```

Replace the template's remote account paths and keep only drives you use. The six fields use literal tabs. Local mountpoints preserve the familiar `~/theia-home`, `~/theia-work`, `~/delta-home`, `~/delta-scratch`, `~/delta-projects`, and `~/perception_wang` layout. The template uses `rw` for normal file access; set a row to `ro` when you want read-only access. The [configuration reference](configuration.md) describes the fields and automation settings.

## Configure SSH once

Create private SSH and connection-sharing directories. Preserve existing keys and configuration.

```sh
umask 077
mkdir -p "$HOME/.ssh/cm"
chmod 700 "$HOME/.ssh" "$HOME/.ssh/cm"
```

Where your institution permits public-key authentication, create a passphrase-protected key for this computer and register only its `.pub` file through the approved account process. Choose a new filename if this one already exists.

```sh
ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519_mownt"
```

Add the following example to `~/.ssh/config`, replacing every address and account. Keep specific entries before broad defaults, because SSH uses its first applicable value. The [SSH configuration manual](https://man.openbsd.org/ssh_config) describes this ordering and connection sharing.

```sshconfig
Host theia
    HostName compute.example.org
    User YOUR_ACCOUNT

Host delta
    HostName cluster.example.org
    User YOUR_ACCOUNT

Host relay-a
    HostName relay-a.example.org
    User YOUR_ACCOUNT

Host relay-b
    HostName relay-b.example.org
    User YOUR_ACCOUNT

Host theia relay-a relay-b
    IdentityFile ~/.ssh/id_ed25519_mownt
    IdentitiesOnly yes

Host theia delta relay-a relay-b
    StrictHostKeyChecking yes
    ControlMaster auto
    ControlPath ~/.ssh/cm/%C
    ControlPersist 12h
    ForwardAgent no
    ForwardX11 no
```

```sh
chmod 600 "$HOME/.ssh/config"
```

Password and multifactor authentication remain available for `delta` without a key. `mownt` opens one shared connection per host, so the host's drives reuse that authenticated session. If you already use a trusted executable at `~/.ssh/delta-login`, the default `DELTA_LOGIN` setting uses it. The helper receives the SSH alias and must establish the same configured master connection. Keep any password retrieval in your local credential store. No helper is required; ordinary SSH prompts work.

To retain an existing helper on a new computer, transfer that reviewed file through a private authenticated channel, keep it owned by your account with mode `700`, and recreate its required local credential-store entry. On macOS, use Keychain Access for that local entry according to the helper's expected service and account names. The helper and credential are separate from this public repository.

For a passphrase-protected key, load it into the SSH agent supplied by your operating system or desktop session. The master can then authenticate without repeated key-passphrase prompts.

```sh
ssh-add "$HOME/.ssh/id_ed25519_mownt"
```

## Verify server identities

Obtain each server's SHA256 host-key fingerprint from an authenticated administrator portal or an independent trusted channel. Make a one-time connection without sharing, compare its displayed fingerprint, and accept it only when it matches.

```sh
ssh -o ControlPath=none -o StrictHostKeyChecking=ask theia
```

Exit that shell and repeat for `delta` and every configured relay. `ssh-keyscan` alone does not authenticate a host. Future connections use strict verification. Confirm that each server exposes the intended path through SFTP if its directory layout is unfamiliar.

```sh
sftp theia
```

Use `pwd` and `ls` in SFTP, then `quit`. The mount table must use paths visible through that subsystem. For a home-relative relay share, the account's shell and SFTP home directories must refer to the same location.

## Enter the share credential locally

Run rclone's interactive configuration and create an SMB remote named `perception`, matching the default `SMB_REMOTE`. Enter your actual server, account, domain, and password at its prompts. The [SMB backend guide](https://rclone.org/smb/) describes those fields and supported authentication methods.

```sh
umask 077
mkdir -p "$HOME/.config/rclone"
chmod 700 "$HOME/.config/rclone"
rclone config
chmod 600 "$HOME/.config/rclone/rclone.conf"
```

Set `SMB_SHARE` in `automation.conf` to the actual share name. If you chose a different remote name or configuration location, update `SMB_REMOTE` or `RCLONE_CONFIG` accordingly. Settings contain names and paths; the credential stays in the private rclone configuration.

Use the ordinary rclone INI configuration with its obscured password field. Whole-file encrypted configurations cannot be merged by the automatic synchronization path. Keep this file and its parent private as shown above.

Configured relay aliases are trusted destinations for this selected SMB credential. `mownt` synchronizes only that named block over authenticated SSH into private files on those accounts. This lets any selected relay mount the share on your behalf. Configure only approved hosts you trust with that access. The [relay guide](relay.md) describes provisioning and credential updates.

If those hosts require Tailscale, install its official client using the [macOS guide](https://tailscale.com/docs/install/mac) or [Linux guide](https://tailscale.com/docs/install/linux) and enroll this computer once. After enrollment, `TAILSCALE=auto` lets `mownt` bring the connection up when needed.

## Start using the drives

Validate the local files, provision the configured relays, and mount everything.

```sh
mownt doctor
mownt setup
mownt
mownt status
```

`setup` is useful for checking initial relay access. Ordinary `mownt` also installs or repairs missing relay components automatically. For daily work, use `mownt`, `mownt -t`, `mownt -d`, or `mownt -p`. Close your files when finished and use `mownt down` to unmount.

When the account's SMB password changes, run `mownt passwd`. Enter the new value at its hidden prompt. The command updates the saved local credential, synchronizes reachable relays, and refreshes the share mounts. A relay that is offline receives the current configuration on a later run.

## Upgrade and uninstall

Unmount, inspect updates, and reinstall over the installed command and templates. Your live private configuration stays in place.

```sh
mownt down
git fetch origin
git log --oneline HEAD..origin/main
git diff HEAD..origin/main
git pull --ff-only
./install.sh --force
mownt doctor
```

To remove the default-prefix client files, unmount and remove the installed command, helper, and templates.

```sh
mownt down
rm -- "$HOME/.local/bin/mownt"
rm -- "$HOME/.local/share/mownt/mounts.example.tsv"
rm -- "$HOME/.local/share/mownt/automation.example.conf"
rm -- "$HOME/.local/share/mownt/libexec/mownt-relay"
rmdir "$HOME/.local/share/mownt/libexec"
rmdir "$HOME/.local/share/mownt"
```

Keep your SSH settings and rclone configuration while other tools still use them. Managed relay files and upstream credentials remain on the configured hosts until you remove them deliberately. Use `rmdir` only for empty, verified unmounted local mountpoint directories. Never recursively delete a mountpoint to uninstall the command.
