# Contributing

Contributions are welcome. Before a major change, open an issue describing the
target macOS version, Clash Verge version, authentication protocol, and the
security impact.

Pull requests should:

- keep passwords out of files, arguments, and environment variables;
- preserve and test idempotent install/uninstall behavior;
- back up user-owned Clash files before mutation;
- avoid bundling subscription or campus credentials;
- run `make test` successfully;
- document any new external dependency.

Core VPN protocol fixes belong upstream in `Mythologyli/zju-connect` whenever
possible. This repository should remain a small lifecycle and configuration
bridge.
