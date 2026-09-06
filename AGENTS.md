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

4. **SwiftUI View Performance**:
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
- `agy_usage_statsTests` uses Swift Testing (`import Testing`) and is annotated with `@Suite(.serialized)` to prevent cache races between concurrent tests.
