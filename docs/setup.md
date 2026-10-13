# Set up a new computer

This guide creates a user-level installation with read-only mounts for its first test. You need an account on each remote server, permission to use SFTP, and the server's host-key fingerprints from its administrator or another authenticated channel. Substitute your own accounts, hostnames, and remote paths for every example.

## Install the filesystem tools

On macOS, install the current macFUSE runtime and its SSHFS package from the [official download page](https://macfuse.github.io/). They are separate installers. Follow the runtime's instructions for your macOS version and restart when required. The [official SSHFS installation guide](https://github.com/macfuse/macfuse/wiki/File-Systems-%E2%80%90-SSHFS) explains how to check its signed installer certificate. macOS already includes Bash and SSH. Install Apple's command-line developer tools if `git` is unavailable.

```sh
xcode-select --install
```

On Debian or Ubuntu, install distribution packages. Debian publishes the [SSHFS package and dependencies](https://packages.debian.org/stable/sshfs).

```sh
sudo apt update
sudo apt install bash git openssh-client sshfs
```

On Fedora, the SSHFS package is named [fuse-sshfs](https://packages.fedoraproject.org/pkgs/fuse-sshfs/fuse-sshfs/).

```sh
sudo dnf install bash git openssh-clients fuse-sshfs
```

For another Linux distribution, use its supported SSHFS and FUSE packages. The runtime needs working user mounts and `fusermount3` or `fusermount`. Containers and managed computers may restrict FUSE even when the command is installed. Run `mownt` as yourself. Administrative privileges are needed only when the operating system requires them to install dependencies.

## Install mownt

Clone the public repository and inspect the source and installation preview. The installer creates `bin/mownt` and `share/mownt/mounts.example.tsv` below its prefix. It does not create a live mount configuration.

```sh
git clone https://github.com/j-vaught/mownt.git
cd mownt
less bin/mownt install.sh
./install.sh --dry-run
./install.sh
export PATH="$HOME/.local/bin:$PATH"
command -v mownt
mownt --help
```

Add the following line once to `~/.zshrc` for an interactive Zsh shell, or to the appropriate startup file for your shell. Open a new terminal afterward.

```sh
export PATH="$HOME/.local/bin:$PATH"
```

A custom prefix beneath your home directory is supported through `./install.sh --prefix "$HOME/tools/mownt"`. Put that prefix's `bin` directory on `PATH` and use its `share/mownt/mounts.example.tsv` in the configuration step below. The installer rejects symlinks and group- or world-writable path components. Review `type -a mownt` if an older installation is already present.

## Create SSH identities and aliases

Create a private SSH directory without replacing existing keys or configuration.

```sh
umask 077
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
```

Where your institution allows public-key authentication, generate a separate passphrase-protected key for this computer. Keep the private key on this computer and register only its `.pub` file with the server through the institution's approved process. Use a new filename if this example already exists.

```sh
ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519_mownt"
```

Add the following entries to `~/.ssh/config`, preserving your existing entries. Put specific host entries before broad `Host *` defaults. Replace all `.example.org` addresses and `YOUR_ACCOUNT` values. SSH chooses its first applicable setting, as described in the [SSH configuration manual](https://man.openbsd.org/ssh_config).

```sshconfig
Host theia
    HostName compute.example.org
    User YOUR_ACCOUNT
    IdentityFile ~/.ssh/id_ed25519_mownt
    IdentitiesOnly yes
    StrictHostKeyChecking yes
    ForwardAgent no
    ForwardX11 no

Host delta
    HostName cluster.example.org
    User YOUR_ACCOUNT
    StrictHostKeyChecking yes
    ForwardAgent no
    ForwardX11 no

Host relay-a
    HostName relay-a.example.org
    User YOUR_ACCOUNT
    IdentityFile ~/.ssh/id_ed25519_mownt
    IdentitiesOnly yes
    StrictHostKeyChecking yes
    ForwardAgent no
    ForwardX11 no

Host relay-b
    HostName relay-b.example.org
    User YOUR_ACCOUNT
    IdentityFile ~/.ssh/id_ed25519_mownt
    IdentitiesOnly yes
    StrictHostKeyChecking yes
    ForwardAgent no
    ForwardX11 no
```

```sh
chmod 600 "$HOME/.ssh/config"
```

The `delta` example deliberately leaves authentication to the server's password and multifactor authentication policy. Do not add passwords to this file, shell scripts, environment variables, or command arguments. Use institutional instructions for certificate, hardware-key, Kerberos, or other required authentication.

## Verify each server before mounting

Obtain the expected SHA256 host-key fingerprints from an authenticated administrator portal, an administrator contacted independently, or an existing trusted management channel. Then make a one-time interactive connection using `ask` and no connection sharing.

```sh
ssh -o ControlPath=none -o StrictHostKeyChecking=ask theia
```

Compare the displayed fingerprint against the independently obtained value before answering `yes`. Stop if they differ. Exit the remote shell after verification, then repeat for every configured alias, including each relay. `ssh-keyscan` alone does not authenticate a server. Do not blindly append its output to `known_hosts`.

Subsequent connections must pass strict checking. Confirm SFTP as well as SSH, because the filesystem uses the SFTP subsystem.

```sh
ssh -o ControlPath=none -o StrictHostKeyChecking=yes theia true
sftp -o ControlPath=none -o StrictHostKeyChecking=yes theia
```

Inside SFTP, use `pwd` and `ls` to find the directory visible to your account, then `quit`. Some managed servers expose paths different from their shell paths. Preserve existing `known_hosts` entries and keep its permissions private.

```sh
chmod 600 "$HOME/.ssh/known_hosts"
```

`mownt` disables connection sharing with `ControlPath=none`, so an existing SSH master does not pre-authenticate it. You may receive a separate password or multifactor prompt for each filesystem. This avoids inheriting trust or forwarding from an older shared connection. If you use multiplexing for unrelated SSH sessions, protect its socket directory with mode `700` and follow the [SSH control-socket guidance](https://man.openbsd.org/ssh_config#ControlPath).

## Create your private mount table

Create the configuration directory and copy the template. These commands use the default installation prefix. Do not replace a configuration you already use.

```sh
umask 077
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mownt"
mkdir -p "$config_dir"
chmod 700 "$config_dir"
test ! -e "$config_dir/mounts.tsv" && cp "$HOME/.local/share/mownt/mounts.example.tsv" "$config_dir/mounts.tsv"
chmod 600 "$config_dir/mounts.tsv"
"${EDITOR:-vi}" "$config_dir/mounts.tsv"
```

Keep only rows you need. Replace remote paths with the paths established through SFTP and use empty dedicated directories beneath your home directory as mountpoints. Leave every row in mode `ro` for the first test. The file uses six literal tab-separated fields. Follow the [configuration reference](configuration.md) when editing it.

## Verify the first mount

Run the local checks and command preview before connecting. `doctor` checks local setup and does not contact servers. A passing result does not establish remote access.

```sh
mownt doctor
mownt --dry-run -t
mownt -t
mownt status
ls "$HOME/mnt/theia-home"
mownt down -t
```

Confirm that the directory contents belong to the expected remote filesystem. If you need write access, edit the intended row from `ro` to `rw`, remount that group, and test a disposable file in an authorized scratch directory. Close the file and confirm it is visible through a separate trusted server session before relying on the mount for work.

Once the direct mounts work, configure [optional relays](relay.md), then test `mownt -p`. Keep a separate backup of important remote data. Filesystem access through SSHFS does not create backups.

## Upgrade and uninstall

Unmount normally and review the update before installing it. The installer requires `--force` to replace the installed command and example template. It leaves the live configuration untouched.

```sh
mownt down
git fetch origin
git log --oneline HEAD..origin/main
git diff HEAD..origin/main
git pull --ff-only
./install.sh --dry-run --force
./install.sh --force
mownt doctor
```

To uninstall the default-prefix files, first stop using the mounts and run a normal unmount. Remove only the installed command and template.

```sh
mownt down
rm -- "$HOME/.local/bin/mownt"
rm -- "$HOME/.local/share/mownt/mounts.example.tsv"
rmdir "$HOME/.local/share/mownt"
```

For a custom prefix, use its corresponding paths. Keep your mount table and SSH settings until you decide whether they are still needed. Remove empty mountpoint directories with `rmdir` only after confirming they are unmounted. Never recursively delete a mountpoint to uninstall the command. Uninstall SSHFS or FUSE separately through the installation method you used if no other applications depend on them.
