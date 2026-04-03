# keepMacClear

A **macOS menu bar app** (Swift / SwiftUI) that shows **live RAM usage**, offers **quick and full memory relief**, and includes optional **security-oriented monitors** (suspicious process spawns, listening ports, DNS checks).

## Features

- **Menu bar**: compact **RAM %** label, color-coded by pressure (normal / warning / critical).
- **Popover dashboard** (~360×500): memory overview, breakdown bar (active / wired / compressed / inactive), top processes, browser memory groups when detected.
- **Quick clean**: `malloc_zone_pressure_relief` — instant, no password (same mechanism as **Auto-clean** when it runs).
- **Full clean**: runs macOS **`purge`** via AppleScript with **administrator privileges** (native password prompt).
- **Auto-clean** (toggle): when **RAM % ≥ alert threshold** (default 85%, configurable in Settings), after a **5‑minute** notification debounce, runs the same allocator relief as Quick clean. Toggle is **not** persisted across launches.
- **Settings**: alert threshold, optional **per-process memory limit** with **auto-kill** and notifications.
- **Spawn monitor**: heuristics for unexpected child processes (e.g. productivity apps spawning shells); optional blocking; process tree view.
- **Port monitor**: rules for risky listening ports; JSON rules under Application Support; optional **close port** (uses `lsof` + signals).
- **DNS monitor**: surface DNS-related status in the dashboard when relevant.

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
| `Sources/keepMacClear/Views/` | SwiftUI dashboard, settings, port/spawn/DNS views |
| `install.sh` | Release build → `/Applications/keepMacClear.app` |

## Safety & privacy

- **Full clean** triggers an **admin** prompt; only use if you understand **`purge`** (disk cache / memory pressure behavior).
- **Auto-kill** and **spawn blocking** can **terminate processes**; review Settings and block lists carefully.
- **Notifications** require a **bundle identifier** (installed `.app`); running via `swift run` may skip some notification paths.

## License

Add or link a `LICENSE` file if you distribute this project.
