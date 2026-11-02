# DontStopClaude

A tiny menu bar app that keeps your Mac awake **with the lid closed**, so Claude (or any long build, download or render) keeps running while your laptop is in your bag.

Closing a MacBook's lid puts it to sleep, and every running job stops. Keep-awake apps like `caffeinate` only stop *idle* sleep. DontStopClaude stops lid sleep too, and turns it back off on its own.

## Install

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/jvalaj/dontstopclaude/main/install.sh | bash
```

It builds the app on your Mac (needs Apple's Command Line Tools, `xcode-select --install`), puts it in `~/Applications`, and opens it at login. You'll be asked for your password once.

## Use

Click the moon in the menu bar. Flip **Don't stop** on, or tap how long Claude can go:

| | |
|---|---|
| **1h** | A quickie |
| **2h** | Just warming up |
| **4h** | Stamina |
| **8h** | All night long |
| **∞** | Don't. Stop. |

The moon turns into a flame and shows the time left. Close the lid.

On macOS 26 the panel uses Liquid Glass.

It turns normal sleep back on when:
- the time runs out,
- the battery drops below 10% while unplugged, or
- you flip it off or choose **I'm done** (quit).

If the lid is closed when time runs out, it puts the Mac to sleep.

## Be careful with heat

A closed laptop in a bag has little airflow. Use the laptop sleeve, don't pack clothes around it, and keep it out of the sun and hot cars.

## How it works

It runs `pmset -a disablesleep 1` (and `0` to undo). The installer adds a rule in `/etc/sudoers.d/dontstopclaude` that lets your user run only those two commands without a password.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/jvalaj/dontstopclaude/main/uninstall.sh | bash
```

## License

MIT
