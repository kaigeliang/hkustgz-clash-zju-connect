#!/bin/zsh

set -euo pipefail

APP_DIR="$HOME/Library/Application Support/HKUSTGZ Clash Bridge"
PLIST="$HOME/Library/LaunchAgents/org.hkustgz.clash-zju-connect.plist"
LABEL="org.hkustgz.clash-zju-connect"
KEYCHAIN_SERVICE="$LABEL"
CLASH_ROOT="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
CLASH_APP="/Applications/Clash Verge.app"
keep_keychain=0

if [[ "${1:-}" == "--keep-keychain" ]]; then
  keep_keychain=1
elif (( $# > 0 )); then
  print -u2 -- "usage: ./uninstall.sh [--keep-keychain]"
  exit 64
fi

username=""
server="remote.hkust-gz.edu.cn"
if [[ -f "$PLIST" ]]; then
  username="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:HKUST_USERNAME' "$PLIST" 2>/dev/null || true)"
  server="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:HKUST_SERVER' "$PLIST" 2>/dev/null || print -r -- "$server")"
fi

was_running=0
if /usr/bin/pgrep -f "$CLASH_APP/Contents/MacOS/clash-verge" >/dev/null 2>&1; then
  was_running=1
  /usr/bin/osascript -e 'tell application "Clash Verge" to quit'
fi

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

if [[ -x "$APP_DIR/clash_enhancer.rb" && -f "$CLASH_ROOT/profiles.yaml" ]]; then
  "$APP_DIR/clash_enhancer.rb" --action remove --root "$CLASH_ROOT" --server "$server"
fi

if (( ! keep_keychain )) && [[ -n "$username" && -x "$APP_DIR/bin/keychain-helper" ]]; then
  "$APP_DIR/bin/keychain-helper" delete "$KEYCHAIN_SERVICE" "$username"
fi

/bin/rm -f "$PLIST"
expected="$HOME/Library/Application Support/HKUSTGZ Clash Bridge"
[[ "$APP_DIR" == "$expected" ]] || { print -u2 -- "Refusing unexpected removal target."; exit 1; }
/bin/rm -rf "$APP_DIR"

if (( was_running )); then
  open "$CLASH_APP"
fi

print -- "Uninstalled HKUSTGZ Clash Bridge. Clash backups were retained."
