# HKUST(GZ) Clash + ZJU Connect Bridge

A lightweight macOS bridge that lets Clash Verge Rev use HKUST(GZ)'s
EasyConnect-compatible VPN without running another desktop app.

> This is an unofficial community project. It is not affiliated with or
> endorsed by HKUST(GZ), Sangfor, Clash Verge Rev, or the zju-connect authors.

The bridge starts `zju-connect` only while Clash Verge is running, exposes it
as a local SOCKS5 node, and adds an `HKUST` group to every existing Clash
subscription profile.

## What it does

- Downloads a pinned upstream `zju-connect` release and verifies SHA-256.
- Stores the VPN password in macOS Keychain, never in configuration files.
- Starts the VPN when Clash Verge starts and stops it when Clash truly exits.
- Restarts `zju-connect` after a crash while Clash remains running.
- Adds `HKUST-VPN` and an `HKUST` selector to all existing remote profiles.
- Routes `10.120.17.114/32` and `10.120.17.115/32` through the HKUST group.
- Backs up every Clash enhancement file before changing it.

Closing the Clash window while it remains in the menu bar does not stop the
VPN. Choosing **Quit** in Clash does.

## Requirements

- macOS 13 or newer, Apple Silicon or Intel
- Clash Verge Rev installed at `/Applications/Clash Verge.app`
- Xcode Command Line Tools (`xcode-select --install`)
- At least one Clash remote subscription already added

## Install

Review the source first, then run from this repository:

```zsh
./install.sh
```

The installer asks for the campus username and password. The username is
stored in the launch agent; the password is sent through an anonymous pipe to
Keychain.

If a new Clash subscription is added later, rerun `./install.sh`. Installation
is idempotent and will add HKUST enhancements to the new profile.

## Verify

With Clash Verge running:

```zsh
lsof -nP -iTCP:1080 -sTCP:LISTEN
nc -vz -w 8 -x 127.0.0.1:7897 -X 5 10.120.17.115 22
```

The Clash **Proxies** page should include an `HKUST` group whose default node
is `HKUST-VPN`.

## Uninstall

```zsh
./uninstall.sh
```

Use `./uninstall.sh --keep-keychain` to retain the saved password. Uninstalling
removes only files managed by this project and semantically removes its Clash
entries; it does not touch subscriptions or other VPN clients.

## Security

See [SECURITY.md](SECURITY.md). In particular, never publish your generated
`clash-verge.yaml`, `profiles.yaml`, subscription files, logs, or Keychain
exports.

## Development

```zsh
make test
```

This repository does not contain or fork the `zju-connect` engine. It downloads
an official, checksum-pinned upstream release. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

The bridge code is MIT licensed. `zju-connect` is a separate AGPL-3.0 project.
