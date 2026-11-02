# DontStopClaude

Close your MacBook lid. Claude keeps working.

Normally, closing the lid puts your Mac to sleep and Claude stops mid-task. DontStopClaude is a menu bar switch that keeps the Mac awake with the lid closed, then turns normal sleep back on by itself.

## Install

Open **Terminal**, paste this, and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/jvalaj/dontstopclaude/main/install.sh | bash
```

Enter your Mac password when asked. That's it. A keyhole appears in your menu bar.

> If it says you need **Command Line Tools**, run `xcode-select --install`, click Install, then paste the command again.

### Or have your AI agent do it

Paste this into Claude Code, Codex, Cursor or any agent that can run commands on your Mac:

```
Install DontStopClaude on my Mac. Run this in Terminal:
curl -fsSL https://raw.githubusercontent.com/jvalaj/dontstopclaude/main/install.sh | bash
If it says Command Line Tools are missing, run xcode-select --install,
wait for it to finish, then run the install command again.
It will ask for my password, so let me type it. Tell me when the
keyhole shows up in my menu bar.
```

## Use

1. Click the keyhole in the menu bar.
2. Pick how long Claude can go:

   | | |
   |---|---|
   | **1h** | A quickie |
   | **2h** | Just warming up |
   | **4h** | Stamina |
   | **8h** | All night long |
   | **∞** | Don't. Stop. |

3. Close the lid.

The key slides into the lock and doesn't stop. A ring around it counts down the time left.

## It stops on its own when

- the time runs out
- the battery drops below 10%
- you flip the switch off, or click **I'm done**

## Heads up

A closed laptop in a bag gets warm. Use the laptop sleeve and keep it out of hot cars.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/jvalaj/dontstopclaude/main/uninstall.sh | bash
```

## How it works

It runs `pmset -a disablesleep 1` to keep the Mac awake and `pmset -a disablesleep 0` to undo it. The installer lets your account run just those two commands without a password, so the switch works with one click.

Requires macOS 11 or later. Liquid Glass on macOS 26.

MIT License
