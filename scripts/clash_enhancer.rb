#!/usr/bin/env ruby

require "fileutils"
require "optparse"
require "tempfile"
require "time"
require "yaml"

options = {
  action: "install",
  root: File.expand_path("~/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"),
  server: "remote.hkust-gz.edu.cn"
}

OptionParser.new do |parser|
  parser.on("--action ACTION", %w[install remove]) { |value| options[:action] = value }
  parser.on("--root PATH") { |value| options[:root] = File.expand_path(value) }
  parser.on("--server HOST") { |value| options[:server] = value }
end.parse!

unless %w[install remove].include?(options[:action])
  warn "action must be install or remove"
  exit 64
end

root = options[:root]
profiles_dir = File.join(root, "profiles")
registry_path = File.join(root, "profiles.yaml")
abort "Clash profile registry not found: #{registry_path}" unless File.file?(registry_path)

def load_yaml(path)
  content = File.read(path)
  YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
rescue Psych::Exception => error
  abort "Invalid YAML in #{path}: #{error.message}"
end

def atomic_yaml_write(path, data)
  mode = File.stat(path).mode & 0o777
  Tempfile.create([File.basename(path), ".tmp"], File.dirname(path)) do |temp|
    temp.write(YAML.dump(data))
    temp.flush
    temp.fsync
    File.chmod(mode, temp.path)
    File.rename(temp.path, path)
  end
end

def array_field(document, key)
  value = document[key]
  return document[key] = [] if value.nil?
  abort "Expected #{key} to be an array" unless value.is_a?(Array)
  value
end

registry = load_yaml(registry_path)
items = registry["items"]
abort "Unexpected profiles.yaml schema" unless items.is_a?(Array)

timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
backup_dir = File.join(root, "clash-verge-rev-backup", "hkust-bridge-#{timestamp}-#{Process.pid}")
backed_up = {}
touched = []

backup = lambda do |path|
  next if backed_up[path]
  FileUtils.mkdir_p(backup_dir)
  FileUtils.cp(path, File.join(backup_dir, File.basename(path)), preserve: true)
  backed_up[path] = true
end

remote_profiles = items.select { |item| item.is_a?(Hash) && item["type"] == "remote" }

remote_profiles.each do |profile|
  option = profile["option"]
  next unless option.is_a?(Hash)

  {
    "merge" => option["merge"],
    "rules" => option["rules"],
    "proxies" => option["proxies"],
    "groups" => option["groups"]
  }.each do |kind, uid|
    next unless uid.is_a?(String) && !uid.empty?
    path = File.join(profiles_dir, "#{uid}.yaml")
    next unless File.file?(path)
    document = load_yaml(path)
    changed = false

    case kind
    when "proxies"
      prepend = array_field(document, "prepend")
      if options[:action] == "install"
        unless prepend.any? { |entry| entry.is_a?(Hash) && entry["name"] == "HKUST-VPN" }
          prepend.unshift({"name" => "HKUST-VPN", "type" => "socks5", "server" => "127.0.0.1", "port" => 1080, "udp" => false})
          changed = true
        end
      else
        before = prepend.length
        prepend.delete_if { |entry| entry.is_a?(Hash) && entry["name"] == "HKUST-VPN" }
        changed = before != prepend.length
      end

    when "groups"
      prepend = array_field(document, "prepend")
      if options[:action] == "install"
        unless prepend.any? { |entry| entry.is_a?(Hash) && entry["name"] == "HKUST" }
          prepend.unshift({"name" => "HKUST", "type" => "select", "proxies" => ["HKUST-VPN", "DIRECT"]})
          changed = true
        end
      else
        before = prepend.length
        prepend.delete_if { |entry| entry.is_a?(Hash) && entry["name"] == "HKUST" }
        changed = before != prepend.length
      end

    when "rules"
      prepend = array_field(document, "prepend")
      managed_rules = [
        "PROCESS-NAME,zju-connect,DIRECT",
        "DOMAIN,#{options[:server]},DIRECT",
        "IP-CIDR,10.120.17.114/32,HKUST,no-resolve",
        "IP-CIDR,10.120.17.115/32,HKUST,no-resolve"
      ]
      if options[:action] == "install"
        managed_rules.reverse_each do |rule|
          unless prepend.include?(rule)
            prepend.unshift(rule)
            changed = true
          end
        end
      else
        before = prepend.length
        prepend.delete_if { |rule| managed_rules.include?(rule) }
        changed = before != prepend.length
      end

    when "merge"
      dns = document["dns"]
      if dns.nil?
        dns = document["dns"] = {}
        changed = options[:action] == "install"
      end
      abort "Expected dns to be a mapping in #{path}" unless dns.is_a?(Hash)
      filters = dns["fake-ip-filter"]
      if filters.nil?
        filters = dns["fake-ip-filter"] = []
        changed = options[:action] == "install"
      end
      abort "Expected dns.fake-ip-filter to be an array in #{path}" unless filters.is_a?(Array)
      managed_filters = [options[:server], "+.hkust-gz.edu.cn"]
      if options[:action] == "install"
        managed_filters.each do |filter|
          unless filters.include?(filter)
            filters << filter
            changed = true
          end
        end
      else
        before = filters.length
        filters.delete_if { |filter| managed_filters.include?(filter) }
        changed = before != filters.length
        dns.delete("fake-ip-filter") if filters.empty?
        document.delete("dns") if dns.empty?
      end
    end

    next unless changed
    backup.call(path)
    atomic_yaml_write(path, document)
    touched << path
  end
end

puts "profiles=#{remote_profiles.length} changed_files=#{touched.uniq.length}"
puts "backup=#{backup_dir}" unless backed_up.empty?
