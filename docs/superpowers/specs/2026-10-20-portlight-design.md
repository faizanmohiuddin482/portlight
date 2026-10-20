# Portlight: design

Date: 2026-10-20 · Status: draft for approval · Name: Portlight (chosen 2026-10-20)

## Intent and why

A native macOS menu-bar app that answers "what is running on which port, is this port free, and can I keep this job alive?" without typing `lsof -i :3000 | xargs kill`.

It is also a **public open-source project built to earn GitHub stars and LinkedIn visibility** for the owner (GitHub `faizanmohiuddin482`). First impressions (icon, README, demo GIF, polish) count as much as the features.

Claude does 100% of the coding, testing and repo management. The owner steers, judges how it looks and feels on a real Mac, does the LinkedIn posting, and buys the Apple Developer account before launch.

## Goals

1. See every listening port at a glance: port, process, PID, user, TCP/UDP, local vs network-reachable, uptime, connection count.
2. Readable names: work out the project from the process's working directory and command line (e.g. `node` on 3000 → "qureos-frontend · next dev").
3. Check whether a port is free and suggest the nearest free one.
4. Quit a process from its row.
5. **Keep awake**, at two levels:
   - **Stay Awake** (lid open): stop idle system sleep while a chosen process is alive (same mechanism as `caffeinate -w <pid>`, an IOPM assertion). The display may still sleep. No password. Released automatically when the process exits, the timer ends, or the app quits.
   - **Lid Closed**: stop all sleep, including lid-close (`pmset -a disablesleep 1`). Needs an admin password. Separate, clearly warned switch.
6. Flag network-exposed ports (bound to `0.0.0.0` / `::` instead of loopback).
7. Find idle and zombie dev processes and clean them up in one action, after showing what will be quit.
8. "Who's keeping my Mac awake?": list every current sleep assertion system-wide (`pmset -g assertions` data), including other apps'.
9. History: per-port usage over the last 7 days, stored locally only.

## Non-goals (v1)

- App Store distribution (its sandbox blocks quitting other processes and `pmset`).
- Docker container mapping, `kubectl port-forward` / SSH tunnel views, Raycast extension, CLI companion, start/stop project "profiles". Good v2 ideas, not in v1.
- Remote machines, a cloud backend, accounts, analytics or telemetry.
- Keeping a single process running *while the Mac sleeps*: macOS can't do this. We prevent sleep instead.

## Anti-goals (a failure even if it works)

- Looking like a generic Electron or web app. It must feel Apple-made.
- **Ever leaving a Mac unable to sleep.** If the app crashes, quits or is force-killed, normal sleep must come back.
- Quitting something the user didn't intend: no silent kills, no killing system processes.
- Sending any data off the machine.
- An unreadable first-run experience (scary warnings with no guidance).

## Design: Apple-native, clean, minimal

Follow Apple's Human Interface Guidelines: SF Pro, SF Symbols, system colours (blue `accent` for "awake", orange for network-exposed, green for healthy), materials/vibrancy, generous spacing, light and dark mode, and respect for Reduce Motion / Increase Contrast. Mockups agreed in brainstorming: Control Center tiles (B) and a System Settings-style window (C), in `docs/design/mockups-apple-style.html` (open in a browser; option A there is the rejected popover list). They set structure and tone, not pixels.

### Menu bar: Control Center panel

- Icon: one plain SF Symbol. It turns accent-blue while anything is keeping the Mac awake.
- Clicking opens a frosted panel of rounded tiles:
  - **Stay Awake**: on/off, showing which process and the time left. Long-press (or a disclosure) to pick a process and a duration.
  - **Lid Closed**: on/off with a warning. Shows its own countdown and safeguards when on.
  - **Listening**: three numbers (total ports, on network, idle). Each opens the window filtered to those ports.
  - **Is port free?**: type a number and get "Free", or who holds it, plus the nearest free port.
  - **Clean Up**: lists idle/zombie processes and asks for confirmation before quitting them.
  - Footer: **Show All Ports…** (opens the window), Settings, Quit.

### Full window: System Settings style

- Sidebar: All Ports, By Project, Stay Awake, On Network, History.
- Main: sortable table (port, process, project, reach, uptime, connections) with ☾ (keep awake) and ✕ (quit) on each row.
- Selecting a row shows a detail pane: full command, working directory, PID, user, and actions (Open in Browser for http-looking ports, Copy URL, Keep Awake, Quit).

## Behaviour rules

- **Refresh**: re-scan ports every 2 s while the panel or window is open, and every 15 s in the background (for history, alerts and the icon state). (Builder may tune.)
- **Quit process**: send SIGTERM, then offer "Force Quit" (SIGKILL) if it is still alive after 3 s. Confirm the first time with a "Don't ask again" option. Processes owned by root or other users, and anything under `/System`, `/usr/libexec` or `/usr/sbin`, show no quit button.
- **Idle/zombie**: a listening process counts as idle when it has had zero established connections and negligible CPU for at least 2 h (setting). "Zombie" means orphaned (parent is launchd/PID 1) and idle. Cleanup only offers the current user's processes.
- **Stay Awake safeguards**: tied to the PID. Released on process exit, timer end (default "until it exits", options 1 h / 2 h / 4 h / custom), or app quit. Several processes can be kept awake at once.
- **Lid Closed modes** (Claude's call): tying it to a process is optional. The user picks a process or "time only"; the maximum duration always applies either way.
- **Lid Closed password** (Claude's call): one admin prompt each time it is turned on. Turning it off early, from the app, needs no second prompt: the app writes a stop flag to a user-owned file that the root watcher polls. The watcher only reads that file and never executes anything from it.
- **Lid Closed safeguards** (defaults are Claude's calls, all adjustable in Settings):
  - maximum duration 4 h;
  - turns off when the battery drops below 20% while unplugged;
  - turns off on a serious thermal state (`ProcessInfo.thermalState == .critical`);
  - turns off when the tied process exits;
  - **survives app crashes**: the restore must not depend on the app being alive. Approach: when enabled, run a small root watcher, started with the admin password through `osascript … with administrator privileges`. It sets `disablesleep 1` and resets it to `0` when any stop condition is met, including the app's own PID dying. The watcher script is passed inline, never as a user-writable file run as root. (A signed `SMAppService` privileged helper can replace this after the Apple Developer account exists.)
  - on app launch, if `disablesleep` is 1 and no watcher is running, offer to restore normal sleep.
- **Network exposure**: a port bound to a non-loopback address is "On Network" and marked orange.
- **Notifications**: only one in v1, "Lid Closed was turned off" (with the reason) when a safeguard stops it. (Claude's call: port pinning is dropped from v1.)
- **History**: local SQLite or JSON in Application Support. 7-day retention for per-port detail, plus small monthly totals (processes cleaned up, hours kept awake) kept for 12 months to feed the share card (Claude's call). Never leaves the machine.

## Constraints

- macOS 14 Sonoma or newer, Apple Silicon and Intel (universal binary).
- Swift 6 + SwiftUI (AppKit where SwiftUI falls short, e.g. the menu-bar panel). No Electron, no web views.
- Build with the Swift command-line tools already on the owner's Mac (Swift 6.3, no full Xcode). Swift Package Manager, plus a script that assembles and ad-hoc signs the `.app` bundle. Must also open in Xcode if someone has it.
- No paid Apple Developer account yet:
  - pre-launch releases are ad-hoc signed and the README explains macOS's "Open Anyway" step with screenshots;
  - before launch day the owner buys the account; releases are then Developer ID-signed and notarized in CI and submitted to Homebrew's main cask catalogue.
- Distribution: GitHub Releases (`.dmg` / `.zip`) + the owner's Homebrew tap (`faizanmohiuddin482/homebrew-tap`). Updates through Sparkle.
- No network calls except Sparkle's update check (which can be turned off).
- Licence: MIT.
- Privacy: reading other users' or root's sockets may be limited without root. Show what is visible; label system-owned ports "System" when the PID can't be resolved. Never ask for root just to list ports.

## Open-source and marketing (part of v1)

- **README is the landing page**: icon, one-line pitch ("Who's on port 3000?"), a 10–15 s demo GIF, a copy-paste install command, a feature list with small screenshots, and first-run instructions.
- Repo hygiene: MIT licence, CONTRIBUTING, issue and PR templates, CHANGELOG, a GitHub Actions build-and-test on every PR, and a release workflow on every `v*` tag.
- A distinctive app icon in the macOS Big Sur+ style (rounded square, depth).
- A shareable moment: a monthly "you cleaned up N processes / kept your Mac awake for N hours" card that people can screenshot.
- Launch plan (the owner runs it; Claude drafts posts in chat, never posts): weekly build-in-public LinkedIn posts with short clips, then one launch day across Show HN, r/macapps, Product Hunt and LinkedIn.
- A GitHub Pages landing page after v1.

## Competition and positioning

Port-viewer Mac apps already exist: Portero (open source), PortCleaner (paid, $4.99), Portie, Port Kill, and PortlessBar. There is also an unrelated Docker dashboard called "port-light". Listing and killing ports is not new, so the README and posts must lead with what is different:
1. **Keep awake per process**, including lid closed with safeguards. None of the apps above combine this with port management.
2. **Project awareness**: "qureos-frontend · next dev", not "node".
3. **Feels Apple-made**: Control Center panel plus a System Settings-style window.
4. Security glance (network-exposed ports) and one-tap zombie cleanup.

## Identity and repo (Claude's calls)

- Name **Portlight**. Repo `faizanmohiuddin482/portlight`, **public from day one** to support build-in-public posts. Bundle ID `io.github.faizanmohiuddin482.portlight`. Sparkle feed served from GitHub Pages. Cask `portlight` in `faizanmohiuddin482/homebrew-tap`.
- No fixed launch date. Order: build v1 → owner tests daily → buy Apple Developer account → signed release → launch day. Homebrew's main catalogue is a post-launch step once the repo has enough stars; at launch the tap is the install path.

## Left to the builder

- Port discovery method (libproc `proc_pidfdinfo` socket info, `netstat -anv`, `lsof`, or a mix), as long as it is fast (<200 ms per scan on a typical dev Mac) and works without root.
- Project-name heuristics (nearest `package.json` / `.git` / `Cargo.toml` / `go.mod` folder name, known-command labels like "next dev", "vite", "postgres").
- Internal architecture, persistence format, test framework (Swift Testing or XCTest, whichever the command-line tools support).
- Exact tile sizes, animations and copy wording within HIG. The owner reviews visuals.
- Icon artwork (a portlight / porthole motif fits the name). Propose two or three options for the owner to pick from.
