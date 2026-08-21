#!/usr/bin/env ruby

require "cgi"

abort "usage: render_launch_agent.rb OUTPUT APP_HOME USERNAME SERVER PORT" unless ARGV.length == 5
output, app_home, username, server, port = ARGV
escape = ->(value) { CGI.escapeHTML(value.to_s) }
script = File.join(app_home, "supervisor.zsh")
log = File.join(app_home, "bridge.log")

xml = <<~PLIST
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
    <key>Label</key>
    <string>org.hkustgz.clash-zju-connect</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/zsh</string>
      <string>#{escape.call(script)}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
      <key>HKUST_BRIDGE_HOME</key>
      <string>#{escape.call(app_home)}</string>
      <key>HKUST_USERNAME</key>
      <string>#{escape.call(username)}</string>
      <key>HKUST_SERVER</key>
      <string>#{escape.call(server)}</string>
      <key>HKUST_PORT</key>
      <string>#{escape.call(port)}</string>
      <key>HKUST_CLASH_APP</key>
      <string>/Applications/Clash Verge.app</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>#{escape.call(log)}</string>
    <key>StandardErrorPath</key>
    <string>#{escape.call(log)}</string>
  </dict>
  </plist>
PLIST

File.write(output, xml, mode: "w", perm: 0o600)
