# Contributing

Preserve the one-command workflow, including authenticated connection sharing, configured relay provisioning and repair, credential synchronization, failover, and mount recovery. Keep compatibility with the system Bash on supported macOS releases and with Linux. Configuration must remain data rather than executable shell. Extend the automated path with narrow validation and ownership checks when its behavior changes.

Before opening a pull request, explain the concrete behavior being fixed, the supported operating systems affected, and the validation performed. Use sanitized examples with reserved example domains and placeholder accounts. Follow [SECURITY.md](SECURITY.md) for vulnerabilities instead of publishing sensitive details.

Run the repository's test suite and available shell checks. Tests must use isolated temporary directories and mocked filesystem/network commands. Do not let a test touch live mounts, read personal credentials, contact institutional servers, or unmount a real filesystem. Cover both successful automation and its failure paths when changing validation, downloads and checksums, credential transport, connection sharing, path handling, process ownership, or mount recovery.

```sh
for script in bin/mownt install.sh libexec/mownt-relay tools/*.sh tests/*.sh; do
    bash -n "$script"
done
bash tests/run.sh
bash tests/relay.sh
bash tests/import-legacy.sh
shellcheck --shell=bash bin/mownt install.sh libexec/mownt-relay tools/*.sh tests/*.sh
```

Install ShellCheck through your supported package source when it is unavailable. The continuous integration workflow is the reference for additional checks and supported runner environments.

Documentation changes should keep the first installation path complete. Recheck CLI examples against `mownt --help`, preserve literal tabs in mount-table examples, and distinguish a local dry run from a successful live mount. Security claims should state the tested boundary and the remaining trust assumptions.

When updating the pinned relay rclone release, verify the new signed checksum manifest using the [official release-signing procedure](https://rclone.org/release_signing/), then verify both supported Linux archives. Update the embedded version and both digests together. The current pin is supported by the [version 1.75.2 signed manifest](https://downloads.rclone.org/v1.75.2/SHA256SUMS). Keep downloaded archives and private test material outside the repository.

Contributions are provided under the repository's MIT license. Identify yourself accurately in commit metadata and do not include secrets or private infrastructure details in commits, fixtures, logs, or issue attachments.
