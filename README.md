# keepMacClear

A **macOS menu bar app** (Swift / SwiftUI) that shows **live RAM usage**, offers **quick and full memory relief**, and bundles **security / network-awareness tools** (listening ports, DNS, suspicious spawns). It does **not** configure macOS’s built-in **Application Firewall** or **pf** — it helps you **see exposure and behavior**, not install packet rules.

## Features

### Memory

- **Menu bar**: compact **RAM %** label, color-coded by pressure (normal / warning / critical).
- **Popover dashboard** (~360×500): memory overview, breakdown bar (active / wired / compressed / inactive), top processes, browser memory groups when detected.
- **Quick clean**: `malloc_zone_pressure_relief` — instant, no password (same mechanism as **Auto-clean** when it runs).
- **Full clean**: runs macOS **`purge`** via AppleScript with **administrator privileges** (native password prompt).
- **Auto-clean** (toggle): when **RAM % ≥ alert threshold** (default 85%, configurable in Settings), after a **5‑minute** notification debounce, runs the same allocator relief as Quick clean. Toggle is **not** persisted across launches.
- **Settings** (gear): RAM alert threshold; optional **per-process memory limit** with **auto-kill** and notifications; toggle for **spawn monitoring**; system info (RAM, cores, macOS version).

### Security & network (often grouped with “firewall-style” awareness)

- **Port monitor** (shield icon in footer, full **Port Monitor** sheet): **TCP bind probe** + rule list for ports that are often risky when left listening (Telnet, RDP, SMB, databases, Docker API, etc.). Rules live in **`~/Library/Application Support/keepMacClear/port-rules.json`** (created with defaults if missing). Notifications when a watched port opens; **Close port** path uses **`/usr/sbin/lsof`** to find listeners then **SIGTERM / SIGKILL** (runs off the main actor). This is **exposure / hardening visibility**, not a firewall engine.
- **Spawn monitor** (exclamation shield, **Spawn Monitor** sheet): periodic scan of new PIDs; flags **parent → child** pairs where “office / mail / preview …” apps spawn **shells, interpreters, or network tools** (heuristic list in code). **Block rules** (persisted in UserDefaults) **auto-kill** matching children; **Events** tab and **Block rules** tab; **Process tree** for monitored parents. Optional notifications.
- **DNS monitor** (antenna icon, **DNS Monitor** sheet): reads resolver config via **SystemConfiguration** (e.g. global / per-service DNS), classifies known public resolvers (Cloudflare, Google, Quad9, OpenDNS vs unknown), aggregates **safe / mixed / unsafe** status, optional **change log** and notifications when server sets change. Dashboard shows a **DNS alert strip** when status is not safe/unknown.

### Popover layout (quick map)

- **Header**: app name + RAM pressure badge.
- **Body** (scroll): **spawn alerts** (if any) → **DNS alert** (if not safe/unknown) → **open ports** summary (if any rule is listening) → **usage** → **browsers** → **top processes**.
- **Footer**: **Auto-clean** · **Quick** · **Full Clean** · **Spawn Monitor** · **Port Monitor** · **DNS Monitor** · **Settings** · **Quit**.

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

Add or link a `LICENSE` file if you distribute this project.
