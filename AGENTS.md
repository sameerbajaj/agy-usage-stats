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

## Testing Guidelines

- Run unit tests with:
  ```bash
  xcodebuild test -project agy-usage-stats.xcodeproj -scheme agy-usage-stats -destination 'platform=macOS' -only-testing:agy-usage-statsTests CODE_SIGN_IDENTITY="-"
  ```
- **Do not run the full UI test suite (`agy_usage_statsUITests`) for routine validation** unless specifically benchmarking launch performance or visual UI regressions. UI tests repeatedly launch the app 7+ times, toggle macOS light/dark appearance, and take ~2 minutes.
- `agy_usage_statsTests` uses Swift Testing (`import Testing`) with fast, deterministic fixture-only tests that do not hit live network ports or scan disk histories. It is annotated with `@Suite(.serialized)`.
