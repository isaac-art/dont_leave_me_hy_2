# HysteriaManager

A native macOS (SwiftUI) menu-bar manager for **Hysteria 2** connections — import
profiles, switch between them from the menu bar, monitor latency/traffic, group
them with URL-test/failover policies, and route **China direct / everything else
through the tunnel** (Clash-style), all powered by hysteria's own ACL engine.

> Built on Linux and synced to your Mac. **Open `HysteriaManager.xcodeproj` in
> Xcode 16+ on macOS 14 (Sonoma) or newer, then ⌘R.** No CocoaPods/SPM deps.

---

## How it works (architecture)

```
 your apps ──► macOS system proxy ──► 127.0.0.1:1080 (SOCKS5) / :8080 (HTTP)
                                          │  = the `hysteria client` subprocess
                                          ▼
                                   hysteria ACL engine
                          ┌───────────────┴────────────────┐
                geoip:cn / geosite:cn / private        everything else
                          │                                  │
                       DIRECT                          your hy2 server
```

- **No TUN, no Network Extension, no $99 developer account.** The CN-direct split
  is done entirely inside hysteria's built-in ACL (`direct`/`reject`/`default` are
  reserved outbounds). The app just generates the right YAML.
- The app runs `hysteria client --config <generated.yaml>` as a child process and
  (optionally) flips the macOS **system proxy** on/off.
- Routing modes per connection:
  - **Rule-based (CN direct)** — `direct(geoip:cn)`, `direct(geosite:cn)`,
    `direct(geoip:private)`, then `default(all)` → proxy.
  - **Global** — everything through the tunnel.
  - **Direct** — bypass (tunnel stays warm but unused).
- You can add **Extra ACL rules** per connection (e.g. `reject(geosite:category-ads-all)`).

## Features

- **Import**: paste `hysteria2://` / `hy2://` share links (bulk, one per line),
  paste a full client YAML, or open a file.
- **Menu bar** (`MenuBarExtra`): status, active connection, live ↑/↓ throughput,
  one-click connection switcher, per-connection latency, group "Test".
- **Management window**: edit every field, preview the generated YAML, see logs.
- **Groups / policies**: `URL test` (connect each member, pick fastest),
  `Failover` (auto-switch on failed health probes), or `Manual`.
- **Monitoring**: latency via a test URL fetched *through* the proxy; traffic via
  `nettop` on the hysteria pid; auto-reconnect awareness.
- **Start on login** (`SMAppService`) and **menu-bar-only vs. Dock** toggle.

## Prerequisites

1. **Xcode 16+** on **macOS 14+**.
2. **The hysteria binary** — bundled into the app (preferred) or installed separately.

### Bundle hysteria inside the app (recommended)

So the app is self-contained (no Homebrew needed at runtime):

1. Download the macOS hysteria binary (or `brew install hysteria` once and copy it):
   ```sh
   # example: grab the universal/arm64 binary, make it executable
   chmod +x ~/Downloads/hysteria
   ```
2. In Xcode, **drag the `hysteria` binary into the `HysteriaManager` group**, check
   the **HysteriaManager** target in the dialog, and choose *Copy items if needed*.
   It lands in **Copy Bundle Resources** → `HysteriaManager.app/Contents/Resources/hysteria`.
3. Keep its executable bit (the `chmod +x` above is preserved on copy). Build & run —
   `BinaryLocator` finds the bundled binary first (see `bundledPath()`).

> Lookup order is: explicit path in Settings → **bundled binary** → Homebrew/MacPorts
> paths → login-shell `PATH`. So bundling "just works", and you can still override.

### Or install it separately

```sh
brew install hysteria
```
Auto-detected from `/opt/homebrew/bin`, `/usr/local/bin`, MacPorts, and your login
shell `PATH`; or set an explicit path in **Settings → General**.

## Build & run

1. Sync this folder to your Mac (it already lives in Syncthing).
2. Open `HysteriaManager/HysteriaManager.xcodeproj`.
3. Select the **HysteriaManager** scheme → **Run** (⌘R).
   - Signing is set to **Sign to Run Locally** (`CODE_SIGN_IDENTITY = "-"`), so it
     builds with no Apple Developer account. If Xcode complains, pick your own team
     under *Signing & Capabilities* (automatic signing).
4. The ⚡️ icon appears in the menu bar. Click it → **Import** or **Manage**.

### Build a Release app into /Applications

Instead of copying the Debug build by hand, run:

```sh
cd HysteriaManager
./build-release.sh
```

It builds the **Release** configuration (ad-hoc signed, runs locally), installs
`HysteriaManager.app` into `/Applications`, and clears the quarantine flag so it
launches without a Gatekeeper prompt.

## First run

1. **Import** a connection (a `hysteria2://` link or YAML).
2. Pick a **Routing mode** (default *Rule-based, CN direct*).
3. Click **Connect**. macOS will prompt for your password the first time it
   changes the **system proxy** (see note below).
4. Watch latency/traffic in the menu bar.

## Permissions & notes

- **System proxy needs admin rights — but you only authorize ONCE.**
  By default macOS asks for your password each time the proxy changes. To stop that,
  open **Settings → Proxy → "Enable passwordless switching (asks once)"**. It installs
  a one-time `sudoers` rule (`/etc/sudoers.d/hysteriamanager`) allowing *just*
  `networksetup` to run without a password, after one admin prompt. After that,
  connect/disconnect never prompts again. "Turn off passwordless switching" removes
  the rule. (Security note: any process running as your user could then toggle the
  system proxy without a password — fine for a personal machine; remove it if that
  matters to you.)
  - If you'd rather not touch the system proxy at all, turn off **"Set macOS system
    proxy"** and point apps at `127.0.0.1:1080` (SOCKS) / `:8080` (HTTP) yourself.
- **GeoIP/GeoSite**: hysteria auto-downloads & caches `geoip.dat`/`geosite.dat` on
  first use. Override the paths in **Settings → Routing** if you keep your own.
- **Start on login** may require approving the app under
  *System Settings → General → Login Items*.
- Data is stored at
  `~/Library/Application Support/HysteriaManager/` (`store.json`, generated
  `configs/*.yaml`, and `hysteria.log`).

## Troubleshooting / logs

When a connection fails (or instantly stops), open the **Log** to see the real
reason — the actual hysteria stderr, the binary path used, config-write errors, proxy
errors, and exit codes are all captured there:

- Menu bar → the **Log** (magnifying-glass) icon, or the **"Show Log"** button that
  appears under an error.
- A connection's toolbar → the magnifying-glass button.
- Or tail the file directly:
  ```sh
  tail -f ~/Library/Application\ Support/HysteriaManager/hysteria.log
  ```
The log persists across launches; use **Clear** in the Log window to reset it.

## Project layout

```
HysteriaManager/
├─ HysteriaManager.xcodeproj         # Xcode 16 synchronized-folder project
└─ HysteriaManager/
   ├─ App/        HysteriaManagerApp.swift     # @main, scenes (menu bar + window + settings)
   ├─ Models/     Models.swift                 # Connection, Group, Settings, RoutingMode
   ├─ Store/      ConnectionStore.swift        # JSON persistence
   ├─ Core/       ConfigBuilder.swift          # YAML + ACL generation (the routing brain)
   │              HysteriaProcess.swift        # subprocess lifecycle
   │              ProxyController.swift         # system proxy via networksetup
   │              ProxyManager.swift           # the runtime engine / app state
   │              URIParser.swift              # hysteria2:// import
   │              BinaryLocator / LatencyTester / TrafficMonitor / LoginItemManager / Shell
   └─ Views/      MenuBarView, MainView, ConnectionDetailView, GroupEditView,
                  ImportView, SettingsView, StatusComponents
```

## Roadmap ideas

- Prompt-free system proxy via a bundled privileged helper.
- Real per-connection cumulative traffic accounting (local counting relay).
- Continuous URL-test for groups (parallel ephemeral probes).
- Optional full TUN mode (Network Extension) for true per-app rules.
- Subscription/airport URL import with auto-update.
