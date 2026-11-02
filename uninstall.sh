#!/bin/bash
# Removes DontStopClaude and turns normal sleep back on.
AGENT="$HOME/Library/LaunchAgents/com.jvalaj.dontstopclaude.plist"
launchctl unload "$AGENT" 2>/dev/null || true
pkill -x DontStopClaude 2>/dev/null || true
sudo /usr/bin/pmset -a disablesleep 0
sudo rm -f /etc/sudoers.d/dontstopclaude
rm -f "$AGENT"
rm -rf "$HOME/Applications/DontStopClaude.app"
defaults delete com.jvalaj.dontstopclaude 2>/dev/null || true
echo "✓ DontStopClaude removed. Your Mac sleeps normally again."
