#!/bin/zsh

set -u
umask 077

APP_DIR="${HKUST_BRIDGE_HOME:?HKUST_BRIDGE_HOME is required}"
SERVER="${HKUST_SERVER:-remote.hkust-gz.edu.cn}"
PORT="${HKUST_PORT:-443}"
USERNAME="${HKUST_USERNAME:?HKUST_USERNAME is required}"
CLASH_APP="${HKUST_CLASH_APP:-/Applications/Clash Verge.app}"
BIN="$APP_DIR/bin/zju-connect"
KEYCHAIN_HELPER="$APP_DIR/bin/keychain-helper"
RUN_DIR="$APP_DIR/run"
PID_FILE="$RUN_DIR/zju-connect.pid"
KEYCHAIN_SERVICE="org.hkustgz.clash-zju-connect"
CLASH_PATTERN="$CLASH_APP/Contents/MacOS/clash-verge"

vpn_pid=""
caffeinate_pid=""

clash_is_running() {
  /usr/bin/pgrep -f "$CLASH_PATTERN" >/dev/null 2>&1
}

vpn_is_running() {
  [[ "$vpn_pid" == <-> ]] && /bin/kill -0 "$vpn_pid" 2>/dev/null
}

stop_vpn() {
  if vpn_is_running; then
    print -- "Clash exited; stopping HKUST VPN (PID $vpn_pid)."
    /bin/kill -TERM "$vpn_pid" 2>/dev/null || true
    for _ in {1..10}; do
      /bin/kill -0 "$vpn_pid" 2>/dev/null || break
      /bin/sleep 1
    done
  fi
  [[ "$caffeinate_pid" == <-> ]] && /bin/kill -TERM "$caffeinate_pid" 2>/dev/null || true
  /bin/rm -f "$PID_FILE"
  vpn_pid=""
  caffeinate_pid=""
}

shutdown_supervisor() {
  stop_vpn
  exit 0
}

start_vpn() {
  [[ -x "$BIN" && -x "$KEYCHAIN_HELPER" ]] || {
    print -u2 -- "Bridge components are incomplete."
    return 1
  }

  if /usr/bin/pgrep -f '/Applications/EasyConnect.app/Contents/Resources/bin/CSClient' >/dev/null 2>&1 || \
     /usr/bin/pgrep -f '/Applications/EasyConnect.app/Contents/Resources/bin/svpnservice' >/dev/null 2>&1; then
    print -u2 -- "Official EasyConnect is running; postponing HKUST VPN start."
    return 1
  fi

  if /usr/sbin/lsof -nP -iTCP:1080 -sTCP:LISTEN >/dev/null 2>&1; then
    print -u2 -- "127.0.0.1:1080 is already occupied."
    return 1
  fi

  local toml_password private_dir config_fifo
  toml_password="$($KEYCHAIN_HELPER read-toml "$KEYCHAIN_SERVICE" "$USERNAME")" || return 1
  private_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/hkust-clash-bridge.XXXXXX")"
  config_fifo="$private_dir/config.fifo"
  /usr/bin/mkfifo -m 600 "$config_fifo"

  (
    {
      print -r -- 'protocol = "easyconnect"'
      print -r -- "server_address = \"$SERVER\""
      print -r -- "server_port = $PORT"
      print -r -- "username = \"$USERNAME\""
      print -r -- "password = $toml_password"
      print -r -- 'disable_zju_config = true'
      print -r -- 'disable_zju_dns = false'
      print -r -- 'socks_bind = "127.0.0.1:1080"'
      print -r -- 'http_bind = ""'
      print -r -- 'tun_mode = false'
      print -r -- 'add_route = false'
      print -r -- 'dns_hijack = false'
      print -r -- 'skip_domain_resource = true'
      print -r -- 'proxy_all = true'
      print -r -- 'zju_dns_server = "auto"'
    } > "$config_fifo"
    /bin/rm -f "$config_fifo"
    /bin/rmdir "$private_dir" 2>/dev/null || true
  ) &
  unset toml_password

  "$BIN" -config "$config_fifo" &
  vpn_pid=$!
  print -r -- "$vpn_pid" > "$PID_FILE"
  /usr/bin/caffeinate -i -w "$vpn_pid" >/dev/null 2>&1 &
  caffeinate_pid=$!
  print -- "Clash detected; starting HKUST VPN (PID $vpn_pid)."
}

/bin/mkdir -p "$RUN_DIR"
/bin/chmod 700 "$APP_DIR" "$RUN_DIR"
/bin/rm -f "$PID_FILE"
trap shutdown_supervisor INT TERM

while true; do
  if clash_is_running; then
    if ! vpn_is_running; then
      stop_vpn
      start_vpn || true
      /bin/sleep 10
    else
      /bin/sleep 2
    fi
  else
    vpn_is_running && stop_vpn
    /bin/sleep 2
  fi
done
