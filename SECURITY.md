# Security policy

## Report a vulnerability

Report security problems through [private vulnerability reporting](https://github.com/j-vaught/mownt/security/advisories/new), or contact J.C. Vaught at `jvaught@sc.edu`. Include the affected revision, operating system, reproducible steps, expected impact, and a minimal sanitized configuration. Do not send real passwords, private keys, institutional data, or unnecessary infrastructure details. Ordinary bugs without security-sensitive details can use the repository's public issue tracker.

## Supported version

Security fixes target the latest release and current `main` branch. Update from a reviewed revision and reinstall the command when a fix affects installed files. No response-time or patch-time commitment is implied.

## Trust model

`mownt` runs with your account's privileges. It trusts the operating system, installed SSH and SSHFS/FUSE binaries, your private SSH configuration, your selected servers, and your account's own files and processes. Remote servers and relays can read or modify the data their access permits. A read-only laptop mount limits writes from that mount; it does not prevent a server or another authorized client from changing the underlying data.

The TSV configuration is parsed as data, with restricted fields and paths, rather than sourced or evaluated. It must be private and user-owned. Mountpoints remain below your home directory and reject symlink components. Existing nonempty directories are not covered by a new mount. These checks reduce accidental misuse and hostile configuration risks; they do not defend against another process already running as your user or an administrator.

SSH host-key verification is strict. Verify initial fingerprints through an independent trusted channel using [setup](docs/setup.md), and investigate key changes. The command disables connection sharing and forwarding on its connections. Your SSH configuration can still direct traffic through a proxy or execute locally configured commands, so its contents and includes must remain trusted. `mownt` neither supplies nor stores authentication secrets.

## Relay and data safety

Relay setup, dependency installation, VPN enrollment, credential storage, and service supervision are manual administrative actions. The command does not download remote binaries, replicate credentials, rotate account passwords, kill unrelated processes, or automatically force-unmount a filesystem. The removed legacy password action only updated saved client credentials, rather than the actual server password.

Each `perception` candidate must pass a connection-time backing-mount check at its resolved remote path. Relative paths resolve beneath the relay account's home, whose shell and SFTP views must agree. This check requires the relay's `mountpoint` command and fails closed when the check fails. The backing share can still disappear after that check, so stop clients before changing relay mounts and verify the backing filesystem before writes. Relays need private configuration and cache directories, least-privilege upstream accounts, and approved access rules. Rclone's obscured password values remain recoverable and must be treated as secrets.

Normal unmounting is the default. Explicit force can interrupt work or discard pending writes. On Linux it requests lazy detachment, which does not establish that the filesystem process exited or data was flushed. SSHFS and any backing cache have their own availability and durability behavior. Close files, resolve upload failures, and verify important data before disconnecting or shutting down a relay. Use independent backups.

## Review scope

The repository's automated checks exercise parsing, validation, command construction, installation behavior, and selected failure paths with mocked tools. They do not establish live server access, institution-specific authentication compatibility, kernel filesystem correctness, or end-to-end write durability. Keep SSHFS, FUSE, SSH, and optional relay dependencies updated through supported sources. No security review can establish the absence of vulnerabilities.
