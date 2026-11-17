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

**Startup:** `viewModel.setup()` → starts `AgyFileWatcher` → reads `history.jsonl` and settings → scans sqlite databases under `conversations/*.db` → aggregates tool calls and LLM generations.

**Refresh:** Real-time refresh happens on `AgyFileWatcher` change callbacks or manual refresh button clicks.

### Cost & Token Estimation Architecture

- **SQLite Database Parsing (`AgyStatsService`):**
  - Reads `steps` table (`metadata` field 1.1) to extract exact step timestamps.
  - Reads `gen_metadata` table to extract prompt tokens (field 1.4.2), output tokens (field 1.4.3), and cached context tokens (field 1.4.5).
  - Correlates each generation with `last_step_index` (field 1.20) to align with chronological query windows `[start, end)`.
- **Official API Billing Formula (`ModelCostInfo`):**
  - `Cost = ((Prompt Tokens * Input Rate) + (Cached Tokens * Cached Rate) + (Output Tokens * Output Rate)) * Regional Multiplier` (`1.0x` Consumer, `1.10x` GCP Vertex AI `'us'`).
  - Gemini 4 Carbon / Argon: $4.00/M in, $0.20/M cached in, $20.00/M out (GCP 1.10x: $4.40 / $0.22 / $22.00).
  - Gemini 4 Hydrogen: $1.50/M in, $0.075/M cached in, $7.50/M out (GCP 1.10x: $1.65 / $0.0825 / $8.25).
  - Gemini 3.7 / 3.8 Flash: $1.50/M in, $0.15/M cached in, $7.50/M out (GCP 1.10x: $1.65 / $0.165 / $8.25).
  - Gemini 3.5 Flash Lite: $0.30/M in, $0.03/M cached in, $2.50/M out (GCP 1.10x: $0.33 / $0.033 / $2.75).
  - Claude Sonnet: $2.00/M in (5.5) / $3.00/M in (4.6), $0.20–$0.30/M cached in, $10.00–$15.00/M out.

### Persistence

- App Settings: `UserDefaults` backed properties.
- Watched files: read-only access to `~/.gemini/antigravity-cli/history.jsonl`, `settings.json`, and `conversations/*.db`.

## Swift/SwiftUI Conventions

- Use **`@Observable`** for view models instead of `ObservableObject` / `@Published`.
- Use **`async/await` + `Task {}`** for asynchronous work.
- Keep components responsive and avoid blocking UI main threads when reading SQLite databases.
- Custom drawing of system graphics (like menu bar icon) uses CoreGraphics (`NSImage`).
