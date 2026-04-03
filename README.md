# keepMacClear

**RAM in the menu bar** for macOS. Click the percentage to see memory use, free RAM with one or two clicks, and optional tools that flag odd ports, DNS, or app behavior.

This app **does not replace** the macOS firewall. It helps you **see** what’s going on and **clean** memory when you want.

## What you can do

- **Watch RAM** — live percentage in the menu bar; open the panel for a breakdown and which apps use the most.
- **Quick clean** — light relief, no password.
- **Full clean** — deeper cleanup; macOS will ask for your password.
- **Auto-clean** — optional: when RAM stays high, it can trigger the same kind of relief as Quick (you can change the threshold in Settings).
- **Port monitor** — heads-up if certain risky ports are listening; you can try to stop what’s using a port.
- **DNS monitor** — see which DNS servers you’re using and if something looks unfamiliar or changed.
- **Spawn monitor** — optional warnings (and blocking) when everyday apps start shells or network tools you might not expect.

## Get started

**From source** (needs macOS 13+ and Swift 6 / current Xcode):

```bash
cd /path/to/keepMacClear
swift run keepMacClear
```

The app lives in the **menu bar only** (no Dock icon).

**Install as an app** in `/Applications`:

```bash
./install.sh
```

Use `sudo ./install.sh` if macOS says you don’t have permission to write to `/Applications`.

## Heads-up

Full clean and some security actions are powerful: they can ask for admin access or **stop processes**. Use them when you understand what you’re doing. For full notifications, install the `.app` (not only `swift run`).

## License

[GNU General Public License v3.0 or later](LICENSE).
