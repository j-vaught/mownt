# Changelog

## 1.1.0 — 2026-10-13

Restores the original one-command workflow. Authenticated SSH connections are shared across mounts, including password and multifactor login. Configured relay hosts are provisioned automatically, receive the selected share credential securely over SSH, and run a managed backing-share helper. Relay failover, Tailscale startup, direct rclone fallback, setup and saved-password update actions, and stale-mount recovery are automated again.

This release supersedes the restrictive 1.0.0 workflow while retaining strict host-key checks, private configuration, pinned relay downloads with checksum verification, scoped credential synchronization, and expected-source checks before mount recovery. Public examples use the original local folder layout and read/write mode.

## 1.0.0 — 2026-10-13

Initial public release of the configurable macOS and Linux SSHFS command. Includes grouped mount, unmount, status, local diagnostics, dry-run output, private tab-separated configuration, ordered relay selection, and user-level installation.

The release replaces personal server settings with sanitized examples and detailed fresh-computer setup. Strict host-key checking, constrained paths, private configuration permissions, explicit force-unmounting, and relay backing-mount checks define the public security baseline. Remote provisioning, credential copying, password helpers, automatic VPN changes, direct SMB/NFS fallback, and broad process termination are excluded.
