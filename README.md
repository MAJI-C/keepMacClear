# keepMacClear

**RAM in the menu bar.** Click the percentage to open a panel: memory breakdown, cleanup buttons, and optional security checks.

## At a glance

| | |
|--|--|
| **See RAM** | Live % in the menu bar; open the popover for usage, memory bar, browsers, heavy apps. |
| **Free memory** | **Quick** — instant, no password. **Full Clean** — deeper macOS clean, asks for your password. **Auto-clean** — runs Quick-style relief when RAM stays high (see Settings). |
| **Risky open ports** | **Port Monitor** — warns if common “bad idea if exposed” ports are listening; you can try to stop the process using that port. |
| **DNS** | **DNS Monitor** — shows which DNS servers you’re using and flags unfamiliar or changed setups. |
| **Odd app behavior** | **Spawn Monitor** — can warn (and optionally block) when normal apps start shells, scripts, or network tools you might not expect. |

It is **not** the macOS firewall. It **watches and alerts**; it does not replace System Settings firewall rules.

## Popover layout

- **Top**: app name and memory pressure (OK / warning / critical).
- **Middle**: alerts (if any) for spawns, DNS, or open ports, then your RAM details.
- **Bottom**: Auto-clean · Quick · Full Clean · Spawn · Ports · DNS · Settings · Quit.

## Feature details (for readers who want more)

### Memory

- Menu bar color matches pressure; popover shows active / wired / compressed / inactive and top processes.
- **Auto-clean** uses the same light relief as **Quick**; it only runs after RAM crosses your alert % and a 5‑minute notification cooldown. The toggle resets when you quit the app.
- **Settings**: change the RAM alert %, optional per-app memory cap with auto-kill, turn spawn monitoring on or off.

### Security & network

- **Port monitor**: editable rules in `~/Library/Application Support/keepMacClear/port-rules.json`; **Close port** uses `lsof` then signals to stop listeners.
- **Spawn monitor**: heuristics + optional persisted block rules (auto-kill matching spawns); events list and process tree in its window.
- **DNS monitor**: reads system DNS via SystemConfiguration; known vs unknown resolvers; change history and notifications optional.

## Requirements

- **macOS 13+** (see `Package.swift` `platforms`).
- **Swift 6** toolchain (Xcode 16+ or matching Swift 6.3+ command-line tools).

## Run from source

```bash
cd /path/to/keepMacClear
swift run keepMacClear
```

The app is **menu-bar only** (no Dock icon). Look for the RAM percentage in the menu bar.

## Install into `/Applications`

Builds **Release**, wraps a proper **`keepMacClear.app`** (with `Info.plist`, `LSUIElement`, notification keys), copies to **`/Applications`**, and opens it:

```bash
./install.sh
```

Use **`sudo ./install.sh`** if writing to `/Applications` fails with permission errors.

## Build & tooling

- **Swift Package Manager** only (`Package.swift`).
- **Swift 6 language mode** and **warnings treated as errors** are enabled on the executable target:

```swift
.swiftLanguageMode(.v6),
.unsafeFlags(["-warnings-as-errors"]),
```

- **Entry point**: `Sources/keepMacClear/AppEntry.swift` (`@main` — do not use `main.swift` as the filename; SwiftPM treats that as top-level entry and it conflicts with `@main`).
- **Concurrency**: core UI and models use **`@MainActor`**; heavy work uses **`Task.detached`** / **`nonisolated static`** helpers where appropriate.

```bash
swift build              # Debug
swift build -c release   # Release (used by install.sh)
```

## Project layout

| Path | Role |
|------|------|
| `Package.swift` | SPM manifest, strict Swift settings |
| `Sources/keepMacClear/AppEntry.swift` | App entry (`@main`) |
| `Sources/keepMacClear/AppDelegate.swift` | `NSApplicationDelegate`, status item, popover, shared `EnvironmentObject`s |
| `Sources/keepMacClear/MemoryMonitor.swift` | RAM stats, timers, threshold / auto-clean / process limit |
| `Sources/keepMacClear/MemoryCleaner.swift` | Allocator relief, `purge`, process signals |
| `Sources/keepMacClear/ProcessSpawnMonitor.swift` | Spawn heuristics and tree |
| `Sources/keepMacClear/PortMonitor.swift` | Port rules, scan, close-port helper |
| `Sources/keepMacClear/DNSMonitor.swift` | DNS status for dashboard |
| `Sources/keepMacClear/Models.swift` | Memory models, byte formatting, `ProcStrings` |
| `Sources/keepMacClear/Views/DashboardView.swift` | Main popover layout, footer tool buttons |
| `Sources/keepMacClear/Views/SettingsView.swift` | Alerts, process limits, spawn toggle |
| `Sources/keepMacClear/Views/PortMonitorView.swift` | Port list, rules, close-port actions |
| `Sources/keepMacClear/Views/SpawnTreeView.swift` | Events, block rules, process tree tabs |
| `Sources/keepMacClear/Views/DNSMonitorView.swift` | DNS servers, status, change history |
| `Sources/keepMacClear/Views/` | Other UI (rows, bars, process rows) |
| `install.sh` | Release build → `/Applications/keepMacClear.app` |

## Safety & privacy

- **Full clean** triggers an **admin** prompt; only use if you understand **`purge`** (disk cache / memory pressure behavior).
- **Auto-kill** and **spawn blocking** can **terminate processes**; review Settings and block lists carefully.
- **Close port** kills whatever **`lsof`** reports on that port — verify it is intentional before using.
- **DNS monitor** reads system DNS configuration only; it does not redirect DNS traffic.
- **Notifications** require a **bundle identifier** (installed `.app`); running via `swift run` may skip some notification paths.

## License

This project is licensed under the **GNU General Public License v3.0 or later**. See the [`LICENSE`](LICENSE) file for the full text.
