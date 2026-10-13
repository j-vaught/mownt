# Security policy

## Report a vulnerability

Report security problems privately to J.C. Vaught at `jvaught@sc.edu`. Include the affected revision, operating system, reproducible steps, impact, and a minimal sanitized configuration. Keep real passwords, private keys, institutional data, and unnecessary infrastructure details out of reports. Ordinary bugs without sensitive details can use the public issue tracker.

## Supported version

Security fixes target the latest release and current `main` branch. Review updates and reinstall when installed files change. No response-time or patch-time commitment is implied.

## Automated operations and trust

`mownt` runs with your account's privileges and automates your configured SSH sessions, network startup, mounts, and approved relay accounts. It trusts the operating system, installed tools, SSH configuration, local login helper, selected servers, and your account's own processes. The mount table and automation settings are strict data files rather than sourced shell code.

The relay aliases in your private configuration are authorized destinations for the selected SMB credential. Provisioning synchronizes only that named rclone block over authenticated SSH into private files, so those relay accounts can mount the share for you. Relay administrators and anyone who compromises those accounts can access that credential and its permitted data. Configure approved trusted hosts and use a share account limited to the required access.

The managed password action reads secrets at hidden prompts and keeps them out of command arguments, source files, dry-run output, and normal logs. An optional private login helper supplies its own trusted local credential mechanism. Rclone's obscured password values remain recoverable and are treated as secrets. `passwd` updates saved client credentials and relays; it does not rotate the actual server account password.

## Connections and provisioning

SSH host-key verification remains strict. Verify first-use fingerprints through an independent trusted channel using [setup](docs/setup.md). Shared SSH masters reuse authenticated sessions so mounts and provisioning can use one host login, including multifactor approval. Control sockets must be private, user-owned, and protected from replacement. Agent and port forwarding are disabled for managed connections.

An optional trusted `delta-login` executable can establish the configured master using an existing local password or credential-store workflow. That helper and your SSH configuration are executable local configuration and belong within your trust boundary. The repository does not contain personal helpers, passwords, private keys, or institutional host settings.

Missing relay rclone binaries are installed from a pinned official artifact only after the expected SHA256 checksum matches. This verifies the downloaded bytes against the reviewed pin. It does not replace trust in the upstream release and the repository revision that supplies the digest. Existing external dependencies remain the responsibility of their supported update channels.

## Filesystem recovery and data

Configuration and mount paths are constrained beneath your home directory with ownership, permission, symlink, and traversal checks. A nonempty unmounted directory is not covered. The command verifies the expected filesystem source before automatic stale recovery or unmounting and does not broadly kill unrelated processes.

Automatic local recovery first attempts a normal unmount and can escalate to force or lazy detachment according to `AUTO_FORCE`. Relay backing-share recovery separately attempts normal unmounting and then lazy detachment when necessary. This restores the original one-command recovery behavior. It can interrupt open files or pending writes. Linux lazy detachment does not establish that a filesystem process exited or that its cache was flushed.

Relay backing mounts are checked before use and repaired by the managed helper. The backing share can disappear after a check, and cached writes can outlive the client operation. Close files before planned disconnection, preserve caches with pending uploads, and verify important data after interrupted operations. Direct fallback uses the same configured SMB share through local rclone. Use independent backups.

On macOS, direct fallback uses rclone's local NFS server bound to loopback. That server has no per-user client authentication, so other local accounts or processes are within its trust boundary. On a shared computer with untrusted local users, set `DIRECT_FALLBACK=no` and use the relay path. The [rclone NFS reference](https://rclone.org/commands/rclone_serve_nfs/) describes this access model.

## Review scope

Automated tests use isolated fixtures and mocked filesystem, SSH, network, provisioning, and credential tools. They cover command construction and selected success and failure paths without contacting live accounts. They do not establish institution-specific authentication compatibility, kernel filesystem correctness, live-server durability, or the absence of vulnerabilities. Keep SSH, SSHFS, FUSE, rclone, and network clients updated through supported sources.
