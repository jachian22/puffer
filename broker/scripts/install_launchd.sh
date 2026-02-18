#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <project_root> [label]"
  exit 1
fi

PROJECT_ROOT="$1"
LABEL="${2:-com.puffer.secure-data-fetcher.broker}"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>

  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/env</string>
    <string>bun</string>
    <string>run</string>
    <string>start</string>
  </array>

  <key>WorkingDirectory</key>
  <string>$PROJECT_ROOT/broker</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>BROKER_HOST</key>
    <string>127.0.0.1</string>
    <key>NODE_ENV</key>
    <string>production</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$PROJECT_ROOT/broker/data/launchd.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$PROJECT_ROOT/broker/data/launchd.stderr.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"

echo "Installed and loaded $LABEL"
echo "Plist: $PLIST_PATH"
