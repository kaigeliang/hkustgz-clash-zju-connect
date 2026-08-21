#!/bin/zsh

set -euo pipefail
umask 077

PROJECT_DIR="${0:A:h}"
APP_DIR="$HOME/Library/Application Support/HKUSTGZ Clash Bridge"
BIN_DIR="$APP_DIR/bin"
PLIST="$HOME/Library/LaunchAgents/org.hkustgz.clash-zju-connect.plist"
LABEL="org.hkustgz.clash-zju-connect"
KEYCHAIN_SERVICE="$LABEL"
CLASH_ROOT="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
CLASH_APP="/Applications/Clash Verge.app"
VERSION="1.2.2"
SERVER="remote.hkust-gz.edu.cn"
PORT="443"
USERNAME=""

usage() {
  print -- "usage: ./install.sh [--username USER] [--server HOST] [--port PORT]"
}

while (( $# > 0 )); do
  case "$1" in
    --username) USERNAME="${2:?missing username}"; shift 2 ;;
    --server) SERVER="${2:?missing server}"; shift 2 ;;
    --port) PORT="${2:?missing port}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -- "unknown option: $1"; usage; exit 64 ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || { print -u2 -- "macOS is required."; exit 1; }
[[ -d "$CLASH_APP" ]] || { print -u2 -- "Clash Verge not found at $CLASH_APP"; exit 1; }
[[ -f "$CLASH_ROOT/profiles.yaml" ]] || { print -u2 -- "Clash Verge profiles not found."; exit 1; }
command -v swiftc >/dev/null || { print -u2 -- "Install Xcode Command Line Tools first."; exit 1; }
command -v ruby >/dev/null || { print -u2 -- "The macOS Ruby runtime is required."; exit 1; }
if [[ ! -f "$PLIST" ]] && /usr/sbin/lsof -nP -iTCP:1080 -sTCP:LISTEN >/dev/null 2>&1; then
  print -u2 -- "Port 1080 is already in use. Stop the existing VPN/proxy before installing."
  exit 1
fi

if [[ -z "$USERNAME" && -f "$PLIST" ]]; then
  USERNAME="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:HKUST_USERNAME' "$PLIST" 2>/dev/null || true)"
fi
if [[ -z "$USERNAME" ]]; then
  print -n -- "HKUST(GZ) username: "
  IFS= read -r USERNAME
fi

[[ "$USERNAME" =~ ^[A-Za-z0-9._@-]+$ ]] || { print -u2 -- "Username contains unsupported characters."; exit 65; }
[[ "$SERVER" =~ ^[A-Za-z0-9.-]+$ ]] || { print -u2 -- "Server must be a hostname."; exit 65; }
[[ "$PORT" == <-> ]] && (( PORT >= 1 && PORT <= 65535 )) || { print -u2 -- "Port must be between 1 and 65535."; exit 65; }

/bin/mkdir -p "$BIN_DIR" "$APP_DIR/run" "$HOME/Library/LaunchAgents"
/bin/chmod 700 "$APP_DIR" "$BIN_DIR" "$APP_DIR/run"

if [[ ! -x "$BIN_DIR/keychain-helper" ]]; then
  /usr/bin/swiftc -O -framework Security "$PROJECT_DIR/src/KeychainHelper.swift" -o "$BIN_DIR/keychain-helper"
  /usr/bin/codesign --force --sign - "$BIN_DIR/keychain-helper"
  /bin/chmod 700 "$BIN_DIR/keychain-helper"
fi

if [[ ! -x "$BIN_DIR/zju-connect" ]]; then
  case "$(uname -m)" in
    arm64)
      asset="zju-connect-darwin-arm64.zip"
      checksum="247141bfc1ad21bd6b5b7741d8697d79c0ff175e8302db73d3d46f3618f619cc"
      ;;
    x86_64)
      asset="zju-connect-darwin-amd64.zip"
      checksum="60e661c11d694ad1fe3fff340b24adb702fa27435fa27ce409f1bc36a019b426"
      ;;
    *) print -u2 -- "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac

  download_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/hkust-bridge-install.XXXXXX")"
  trap '/bin/rm -rf "$download_dir"' EXIT
  archive="$download_dir/$asset"
  url="https://github.com/Mythologyli/zju-connect/releases/download/v$VERSION/$asset"
  print -- "Downloading zju-connect v$VERSION…"
  /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 "$url" --output "$archive"
  actual="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
  [[ "$actual" == "$checksum" ]] || { print -u2 -- "Checksum mismatch."; exit 1; }
  /usr/bin/ditto -x -k "$archive" "$download_dir/extracted"
  engine="$(find "$download_dir/extracted" -type f -name zju-connect -print -quit)"
  [[ -n "$engine" ]] || { print -u2 -- "zju-connect was not found in the archive."; exit 1; }
  /bin/cp "$engine" "$BIN_DIR/zju-connect"
  /bin/chmod 700 "$BIN_DIR/zju-connect"
  print -r -- "$VERSION" > "$APP_DIR/engine-version"
  /bin/rm -rf "$download_dir"
  trap - EXIT
fi

if ! "$BIN_DIR/keychain-helper" read-toml "$KEYCHAIN_SERVICE" "$USERNAME" >/dev/null 2>&1; then
  print -- "A secure macOS password dialog will open."
  set -o pipefail
  /usr/bin/osascript \
    -e 'set promptResult to display dialog "Enter the HKUST(GZ) VPN password" default answer "" with title "HKUSTGZ Clash Bridge" with hidden answer buttons {"Cancel", "Save to Keychain"} default button "Save to Keychain" cancel button "Cancel"' \
    -e 'return text returned of promptResult' \
    | "$BIN_DIR/keychain-helper" store "$KEYCHAIN_SERVICE" "$USERNAME"
fi

/bin/cp "$PROJECT_DIR/scripts/supervisor.zsh" "$APP_DIR/supervisor.zsh"
/bin/cp "$PROJECT_DIR/scripts/clash_enhancer.rb" "$APP_DIR/clash_enhancer.rb"
/bin/chmod 700 "$APP_DIR/supervisor.zsh" "$APP_DIR/clash_enhancer.rb"

"$APP_DIR/clash_enhancer.rb" --action install --root "$CLASH_ROOT" --server "$SERVER"

was_running=0
if /usr/bin/pgrep -f "$CLASH_APP/Contents/MacOS/clash-verge" >/dev/null 2>&1; then
  was_running=1
  /usr/bin/osascript -e 'tell application "Clash Verge" to quit'
  for _ in {1..20}; do
    /usr/bin/pgrep -f "$CLASH_APP/Contents/MacOS/clash-verge" >/dev/null 2>&1 || break
    /bin/sleep 1
  done
fi

user_id="$(id -u)"
launchctl bootout "gui/$user_id/$LABEL" 2>/dev/null || true
"$PROJECT_DIR/scripts/render_launch_agent.rb" "$PLIST" "$APP_DIR" "$USERNAME" "$SERVER" "$PORT"
/usr/bin/plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "gui/$user_id" "$PLIST"

if (( was_running )); then
  open "$CLASH_APP"
  ready=0
  for _ in {1..55}; do
    if /usr/sbin/lsof -nP -iTCP:1080 -sTCP:LISTEN >/dev/null 2>&1; then ready=1; break; fi
    /bin/sleep 1
  done
  (( ready )) || { print -u2 -- "Installed, but port 1080 did not become ready. Check $APP_DIR/bridge.log"; exit 1; }
fi

print -- "Installed successfully. Start Clash Verge to start HKUST VPN."
