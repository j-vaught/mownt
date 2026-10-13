# Contributing

Keep changes focused on explicit user-level mount operations. Preserve compatibility with the system Bash on supported macOS releases and with Linux. Configuration must remain data rather than executable shell, authentication must stay with SSH, and remote administration must remain explicit.

Before opening a pull request, explain the concrete behavior being fixed, the supported operating systems affected, and the validation performed. Use sanitized examples with reserved example domains and placeholder accounts. Follow [SECURITY.md](SECURITY.md) for vulnerabilities instead of publishing sensitive details.

Run the repository's test suite and available shell checks. Tests must use isolated temporary directories and mocked filesystem/network commands. Do not let a test touch live mounts, read personal credentials, contact institutional servers, or unmount a real filesystem. Add failure-path coverage when changing configuration validation, path handling, subprocess arguments, mount ownership, or unmount behavior.

```sh
bash -n bin/mownt install.sh tests/run.sh
bash tests/run.sh
shellcheck bin/mownt install.sh tests/run.sh
```

Install ShellCheck through your supported package source when it is unavailable. The continuous integration workflow is the reference for additional checks and supported runner environments.

Documentation changes should keep the first installation path complete. Recheck CLI examples against `mownt --help`, preserve literal tabs in mount-table examples, and distinguish a local dry run from a successful live mount. Security claims should state the tested boundary and the remaining trust assumptions.

Contributions are provided under the repository's MIT license. Identify yourself accurately in commit metadata and do not include secrets or private infrastructure details in commits, fixtures, logs, or issue attachments.
