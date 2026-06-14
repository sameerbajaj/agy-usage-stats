# CLAUDE.md

This file provides guidance when working with code in this repository.

## Project Overview

**Antigravity Usage Stats** is a macOS menu bar app (SwiftUI) that monitors Antigravity CLI (`agy`) usage statistics across local projects. It displays the number of queries run today in the menu bar and provides detailed breakdowns (workspaces, tool calls, search history) in a popover window.

## Build & Verification

**Run a local debug build:**
```bash
xcodebuild -project agy-usage-stats.xcodeproj -scheme agy-usage-stats -configuration Debug build
```

**Build DMG releases:**
```bash
./scripts/build-dmg.sh v1.0.0
```

Always report build status explicitly (`BUILD SUCCEEDED` or failure reason) in handoff summaries.

## Architecture

### Layers

- **`@main` app** (`agy_usage_statsApp.swift`) — Sets up `MenuBarExtra` owning `MenuBarPopover` and renders the custom gravity chevron icon in `MenuBarLabel`.
- **ViewModel** (`ViewModels/AgyStatsViewModel.swift`) — `@Observable` class holding UI state, managing history search queries, and persisting settings in `UserDefaults`.
- **Views** (`Views/`) — Dumb SwiftUI views: `MenuBarPopover` (tab container), `StatsTabView` (metric grid & tool breakdowns), `WorkspacesTabView` (active projects list), `HistoryTabView` (searchable log), and `SettingsTabView` (path editor).
- **Services** (`Services/`) — Namespaces and helper classes:
  - `AgyStatsService`: Parses JSON Lines `history.jsonl`, reads `settings.json`, and queries SQLite conversation `.db` files directly using C bindings (`SQLite3`).
  - `AgyFileWatcher`: Lightweight file checker that polls `history.jsonl` modification times to trigger auto-refreshes.
- **Models** (`Models/`) — Value types: `QueryEntry` (prompt data), `WorkspaceStats` (per-project count), `ToolStat` (protobuf wire tag matched counts), `AgyUsageStats` (unified stats payload), and `AgySettings` (CLI configs).

### Key Data Flow

**Startup:** `viewModel.setup()` → starts `AgyFileWatcher` → reads `history.jsonl` and settings → scans sqlite databases under `conversations/*.db` → aggregates tool calls.

**Refresh:** Real-time refresh happens on `AgyFileWatcher` change callbacks or manual refresh button clicks.

### Persistence

- App Settings: `UserDefaults` backed properties.
- Watched files: read-only access to `~/.gemini/antigravity-cli/history.jsonl`, `settings.json`, and `conversations/*.db`.

## Swift/SwiftUI Conventions

- Use **`@Observable`** for view models instead of `ObservableObject` / `@Published`.
- Use **`async/await` + `Task {}`** for asynchronous work.
- Keep components responsive and avoid blocking UI main threads when reading SQLite databases.
- Custom drawing of system graphics (like menu bar icon) uses CoreGraphics (`NSImage`).
