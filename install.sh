#!/bin/bash
# DontStopClaude installer: builds the app on your Mac and adds it to the menu bar.
# Usage: curl -fsSL https://raw.githubusercontent.com/jvalaj/dontstopclaude/main/install.sh | bash
set -euo pipefail

REPO="jvalaj/dontstopclaude"
APP_DIR="$HOME/Applications/DontStopClaude.app"
AGENT="$HOME/Library/LaunchAgents/com.jvalaj.dontstopclaude.plist"
SUDOERS="/etc/sudoers.d/dontstopclaude"

[ "$(uname)" = "Darwin" ] || { echo "DontStopClaude only runs on macOS."; exit 1; }

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "DontStopClaude needs Apple's Command Line Tools to build."
  echo "Run: xcode-select --install   then run this installer again."
  exit 1
fi

echo "→ Downloading"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/Sources/main.swift" -o "$tmp/main.swift"

echo "→ Building"
build="$tmp/DontStopClaude.app"
mkdir -p "$build/Contents/MacOS"
xcrun swiftc -O "$tmp/main.swift" -o "$build/Contents/MacOS/DontStopClaude" -framework AppKit
cat > "$build/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>DontStopClaude</string>
  <key>CFBundleIdentifier</key><string>com.jvalaj.dontstopclaude</string>
  <key>CFBundleExecutable</key><string>DontStopClaude</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$build" >/dev/null 2>&1 || true

echo "→ Installing"
pkill -x DontStopClaude 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP_DIR"
cp -R "$build" "$APP_DIR"

echo "→ Letting the app switch sleep on and off without asking for your password"
echo "  (allows only 'pmset -a disablesleep 0/1'; you may be asked for your password once)"
rule="$tmp/sudoers"
echo "$(id -un) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$rule"
if sudo /usr/sbin/visudo -cf "$rule" >/dev/null; then
  sudo install -m 0440 -o root -g wheel "$rule" "$SUDOERS"
fi

echo "→ Opening at login"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.jvalaj.dontstopclaude</string>
  <key>ProgramArguments</key><array><string>$APP_DIR/Contents/MacOS/DontStopClaude</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
launchctl unload "$AGENT" 2>/dev/null || true
launchctl load "$AGENT" 2>/dev/null || open "$APP_DIR"

echo ""
echo "✓ DontStopClaude is in your menu bar (the 😴). Click it and flip Don't stop on."
