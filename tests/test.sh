#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
fixture="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/hkust-bridge-test.XXXXXX")"
trap '/bin/rm -rf "$fixture"' EXIT

/bin/zsh -n "$PROJECT_DIR/install.sh"
/bin/zsh -n "$PROJECT_DIR/uninstall.sh"
/bin/zsh -n "$PROJECT_DIR/scripts/supervisor.zsh"
/usr/bin/ruby -c "$PROJECT_DIR/scripts/clash_enhancer.rb" >/dev/null
/usr/bin/ruby -c "$PROJECT_DIR/scripts/render_launch_agent.rb" >/dev/null
/usr/bin/swiftc -typecheck -framework Security "$PROJECT_DIR/src/KeychainHelper.swift"

/bin/mkdir -p "$fixture/profiles"
/usr/bin/ruby -ryaml -e '
  root = ARGV[0]
  registry = {
    "current" => "remote-a",
    "items" => [
      {"uid" => "remote-a", "type" => "remote", "name" => "fixture", "option" => {
        "merge" => "merge-a", "rules" => "rules-a", "proxies" => "proxies-a", "groups" => "groups-a"
      }}
    ]
  }
  File.write(File.join(root, "profiles.yaml"), YAML.dump(registry))
  File.write(File.join(root, "profiles", "merge-a.yaml"), YAML.dump({"profile" => {"store-selected" => true}}))
  %w[rules proxies groups].each do |kind|
    File.write(File.join(root, "profiles", "#{kind}-a.yaml"), YAML.dump({"prepend" => [], "append" => [], "delete" => []}))
  end
' "$fixture"

first="$($PROJECT_DIR/scripts/clash_enhancer.rb --action install --root "$fixture")"
print -r -- "$first" | /usr/bin/grep -q 'changed_files=4'

/usr/bin/ruby -ryaml -e '
  root = ARGV[0]
  proxy = YAML.safe_load(File.read(File.join(root, "profiles", "proxies-a.yaml")))
  group = YAML.safe_load(File.read(File.join(root, "profiles", "groups-a.yaml")))
  rules = YAML.safe_load(File.read(File.join(root, "profiles", "rules-a.yaml")))
  merge = YAML.safe_load(File.read(File.join(root, "profiles", "merge-a.yaml")))
  abort unless proxy["prepend"].count { |x| x["name"] == "HKUST-VPN" } == 1
  abort unless group["prepend"].count { |x| x["name"] == "HKUST" } == 1
  abort unless rules["prepend"].include?("IP-CIDR,10.120.17.115/32,HKUST,no-resolve")
  abort unless merge.dig("dns", "fake-ip-filter").include?("remote.hkust-gz.edu.cn")
' "$fixture"

second="$($PROJECT_DIR/scripts/clash_enhancer.rb --action install --root "$fixture")"
print -r -- "$second" | /usr/bin/grep -q 'changed_files=0'

$PROJECT_DIR/scripts/clash_enhancer.rb --action remove --root "$fixture" >/dev/null
/usr/bin/ruby -ryaml -e '
  root = ARGV[0]
  proxy = YAML.safe_load(File.read(File.join(root, "profiles", "proxies-a.yaml")))
  group = YAML.safe_load(File.read(File.join(root, "profiles", "groups-a.yaml")))
  rules = YAML.safe_load(File.read(File.join(root, "profiles", "rules-a.yaml")))
  abort if proxy["prepend"].any? { |x| x["name"] == "HKUST-VPN" }
  abort if group["prepend"].any? { |x| x["name"] == "HKUST" }
  abort if rules["prepend"].any? { |x| x.to_s.include?("HKUST") || x.to_s.include?("zju-connect") }
' "$fixture"

plist="$fixture/agent.plist"
$PROJECT_DIR/scripts/render_launch_agent.rb "$plist" "$fixture/App Home" "student01" "remote.hkust-gz.edu.cn" "443"
/usr/bin/plutil -lint "$plist" >/dev/null

rg_bin="$(command -v rg || true)"
if [[ -n "$rg_bin" ]] && "$rg_bin" -n --glob '!tests/test.sh' 'kgliang033|jp1\.tccccc|WgikZKcSfdR4|set-your-secret' "$PROJECT_DIR"; then
  print -u2 -- "Possible personal secret found in repository."
  exit 1
fi
if [[ -z "$rg_bin" ]] && /usr/bin/grep -R --exclude='test.sh' -E -n 'kgliang033|jp1\.tccccc|WgikZKcSfdR4|set-your-secret' "$PROJECT_DIR"; then
  print -u2 -- "Possible personal secret found in repository."
  exit 1
fi

tracked_forbidden="$(find "$PROJECT_DIR" -type f \( -name 'clash-verge.yaml' -o -name 'profiles.yaml' \) -print)"
[[ -z "$tracked_forbidden" ]] || { print -u2 -- "Generated Clash configuration found in repository."; exit 1; }

print -- "All tests passed."
