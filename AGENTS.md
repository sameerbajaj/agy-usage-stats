# AGENTS.md

Context and operational guidelines for agentic development on **agy-usage-stats**.

## Architecture & Performance Decisions

1. **Kernel File Watching (`AgyFileWatcher`)**:
   - Never poll the filesystem by traversing `conversations/*.db` files (doing so previously pegged CPU at 90.4% across 500+ databases).
   - Use macOS kernel kqueue event monitors (`DispatchSource.makeFileSystemObjectSource`) on `history.jsonl` and the `conversations/` directory with a debounced handler and lightweight fallback.

2. **Stats In-Memory Caching (`AgyStatsService`)**:
   - A top-level signature cache check (`statsCache`) sits at the very entrance of `loadStats(cliDir:)`.
   - Keyed on `(settings, startOfToday, histMod, histSize, convDirMod)`.
   - Returns in `< 1ms` on warm loads without re-parsing SQLite databases or JSON files.

3. **Quota Service Optimization (`AgyQuotaService`)**:
   - Do NOT run slow `/bin/ps` table scans.
   - Use direct listening socket lookups via `lsof -nP -iTCP -sTCP:LISTEN -c agy -a`.
   - Prioritize FD `10u` Connect protocol ports to hit the target API immediately.
   - Use shared `URLSession` with 0.5s connection timeouts and parallel port probing.
   - Maintain `lastActivePort` across cache clears and cache responses for 30s (15s for nil).
   - **CSRF Token Header**: AGY language servers mandate `x-codeium-csrf-token`. Resolved via `ANTIGRAVITY_CSRF_TOKEN` or `~/.gemini/antigravity-cli/csrf_token`.
    - **Subscription Priority over GCP Direct Billing**: Subscription quotas always take precedence in the menu bar and icon. When multiple sessions are open, `AgyQuotaService` requires non-empty quota groups (`!info.groups.isEmpty`) to declare a port winner, preventing empty direct-GCP sessions from masking subscription limits. GCP project context remains visible in the popover header and Cost tab.

4. **Multi-Session Dynamic Model Tracking & Depletion Awareness**:
   - `getActiveGroup()` in `AgyStatsViewModel` dynamically tracks recent query activity across all active terminals and workspaces (`stats.recentQueries`).
   - When multiple models are queried across different concurrent sessions (e.g. Sonnet configured in `settings.json` or one terminal, but Gemini actively running in others), the app automatically selects the model that is **actively getting depleted** (the lowest remaining quota fraction).
   - Provides `IconModelSelection.mostDepleted` in addition to `.active` to allow explicitly locking the menu bar icon to whichever quota group is closest to its limit.
   - Dynamic `activeModelDisplayName` surfaces the actual active query model in the UI rather than statically displaying the `settings.json` model.
   - Menu bar item features native macOS hover tooltip (`.help`) detailing active model, Gemini/Claude percentages, and queries today.

5. **SwiftUI View Performance**:
   - Always use `LazyVStack` inside `ScrollView` for lists with hundreds/thousands of entries (`HistoryTabView`, `WorkspacesTabView`).
   - Never instantiate `DateFormatter`, `ISO8601DateFormatter`, or `RelativeDateTimeFormatter` inside view bodies or row structs; declare them as static singletons.
   - Cache dynamic CoreGraphics drawing results (`NSImage`) by key for menu bar icons.
   - Precompute and memoize expensive aggregations in views (e.g., `CostTabView`).

6. **Model Catalog & Frontier Pricing Engine**:
   - **Gemini 4 Argon**: Introductory pricing at $2.00 / MTok input, $10.00 / MTok output, and $0.10 / MTok cached input (95% discount). Tiers mapped across `Low`, `Medium`, and `High`. Pattern mapping in [`AgyStatsService.cleanAndMapModelName`](file:///Users/sameerbajaj/PARA/Projects/dev/agy-usage-stats/agy-usage-stats/Services/AgyStatsService.swift) matches `argon`, `gemini-4-argon`, and `gemini-argon`.
   - **Claude Sonnet 5.5**: $2.00 / MTok input, $10.00 / MTok output, and $0.20 / MTok cached input across `Low`, `Medium`, and `High` effort tiers.
   - **Claude Opus 5.5**: $4.00 / MTok input, $20.00 / MTok output, and $0.20 / MTok cached input across `Low`, `Medium`, and `High` effort tiers.
   - **Historical Backwards Compatibility**: Retains `Claude Sonnet 4.6 (Thinking)` and `Claude Opus 4.6 (Thinking)` for earlier sessions; date validity enforcement cleanly falls back pre-Sep 2026 runs.
   - **Quota Group & UI Synergy**: [`AgyStatsViewModel`](file:///Users/sameerbajaj/PARA/Projects/dev/agy-usage-stats/agy-usage-stats/ViewModels/AgyStatsViewModel.swift) seamlessly binds `argon` queries to Gemini quota groups and `sonnet`/`opus` to Claude & GPT quota groups.

7. **UI Information Architecture & Visual Design Invariants**:
   - **Terminal-Native Alignment**: Always mirror the exact model categorization and structure from the official Antigravity CLI `/usage` terminal modal (`GEMINI MODELS`, `CLAUDE AND GPT MODELS`, `GEMINI 4 ARGON`).
   - **Readability Over Gimmicks**: Avoid cramped micro-charts, SVG donuts, or dense bar scrubbers in popovers. Use spacious, high-contrast progress bars, exact percentage indicators (`83.14%`), and human-friendly reset countdowns (`Refreshes in 5 days, 23 hours`).
   - **Clean 2-Tab Architecture**: Structure the popover strictly around 2 primary tabs: `Usage & Cost` (single unified sheet with quotas + cost by model) and `Settings`.
   - **Cost Breakdown by Model**: Keep cost breakdowns simple, bold, and organized by model with direct proportion bars, bold price, and token counts, supporting `Today | Last 7 Days | Last 30 Days`.

## Testing Guidelines

- Run unit tests with:
  ```bash
  xcodebuild test -project agy-usage-stats.xcodeproj -scheme agy-usage-stats -destination 'platform=macOS' -only-testing:agy-usage-statsTests CODE_SIGN_IDENTITY="-"
  ```
- **Do not run the full UI test suite (`agy_usage_statsUITests`) for routine validation** unless specifically benchmarking launch performance or visual UI regressions. UI tests repeatedly launch the app 7+ times, toggle macOS light/dark appearance, and take ~2 minutes.
- `agy_usage_statsTests` uses Swift Testing (`import Testing`) with fast, deterministic fixture-only tests that do not hit live network ports or scan disk histories. It is annotated with `@Suite(.serialized)`.
