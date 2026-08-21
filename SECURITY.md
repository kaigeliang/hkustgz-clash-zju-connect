# Security policy

## Credential boundary

- The VPN password is stored as a Generic Password in macOS Keychain.
- The password is never written to TOML, YAML, plist, logs, command-line
  arguments, or environment variables.
- At runtime, the password travels through anonymous pipes and a mode-0600
  FIFO. The FIFO and its private temporary directory are removed immediately.
- Local SOCKS5 listens only on `127.0.0.1:1080`.

The campus username, server hostname, and port are not treated as secrets and
appear in the user's launch agent.

## Files that must never be committed

- `clash-verge.yaml`
- `profiles.yaml` and downloaded subscription YAML files
- VPN or Clash logs
- Keychain exports
- screenshots containing subscription URLs, UUIDs, passwords, or tokens

## Dependency boundary

The installer downloads a fixed upstream `zju-connect` version and verifies
the archive before extraction. A version update must include both new platform
checksums and a successful lifecycle/connectivity test.

## Reporting

Do not include credentials or full Clash configurations in a bug report.
Provide redacted logs and the macOS, Clash Verge, and `zju-connect` versions.
