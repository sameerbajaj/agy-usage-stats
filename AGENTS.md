# AGENTS.md

Context and operational guidelines for agentic development on **agy-usage-stats**.

## Architecture & Performance Decisions

1. **Kernel File Watching (`AgyFileWatcher`)**:
   - Never poll the filesystem by traversing `conversations/*.db` files (doing so previously pegged CPU at 90.4% across 500+ databases).
   - Use macOS kernel kqueue event monitors (`DispatchSource.makeFileSystemObjectSource`) on both consumer (`~/.gemini/antigravity-cli`) and GCP (`~/.agy-gcp-home/.gemini/antigravity-cli`) `history.jsonl` and `conversations/` directories (`gcpConvDirSource`) with a debounced handler and lightweight fallback.

2. **Stats In-Memory Caching (`AgyStatsService`)**:
   - A top-level signature cache check (`statsCache`) sits at the very entrance of `loadStats(cliDir:)`.
   - Keyed on both consumer and GCP paths: `(settings, startOfToday, histMod, histSize, convDirMod, gcpHistoryModDate, gcpHistorySize, gcpConversationsDirModDate)`.
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

8. **Multi-Box Ingestion & Account Switching (Direction 1 Capsule)**:
   - **Dual Data Ingestion**: Concurrently monitors and ingests usage and queries from both `~/.gemini/antigravity-cli` (Consumer Subscription box) and `~/.agy-gcp-home/.gemini/antigravity-cli` (Google Cloud Platform $300 credit box via `agy-gcp`).
   - **Segmented Header Capsule**: Uses Direction 1 (`[ All | ● Sub | ☁️ GCP ]`) in `OverviewTabView` header. Persists selection via `@AppStorage("agy_selectedAccountFilter")`.
   - **GCP Credit Card**: When `GCP` or `All` is selected, renders a dedicated card detailing GCP Cloud Spend (today's spend, 7-day spend, total consumed) whenever `gcpTotalCost > 0 || gcpTodayCost > 0`. If a custom budget pool is configured in Settings (`gcpCreditPool > 0`), it dynamically renders the remaining balance and progress bar; when set to 0, it renders clean spend tracking.
   - **Unified CoreGraphics Menu Bar Canvas (`AgyMenuBarRenderer`)**: The entire menu bar status item (circle ring gauge + remaining percentage + optional spend badge) is rendered inside a single cohesive `NSImage` (`makeAntigravityImage`). Never append external SwiftUI `Text` or 3D emoji (`☁️`) next to the icon.
   - **Zero Model Prefixes (`34%`, Never `G: 34%`)**: Regardless of which model is tracked (`Active`, `Most Depleted`, `Gemini`, `Gemini 4 Argon`, `Claude`), the menu bar always renders a clean remaining percentage (`34%`) without `G:`, `C:`, or `A:` prefixes.
   - **Decoupled Circle Ring & Percentage Number**: Users can independently configure the **Percentage Number** (`iconQuotaLimitTarget`: `5-Hour Limit`, `Weekly Limit`, `Auto`) and the **Circle Ring Gauge** (`iconCircleFillMetric`: `Weekly Limit`, `5-Hour Limit`, `Match Percentage`)—e.g., showing the Weekly limit on the circle ring and the 5-Hour limit as the percentage number.
   - **Health Color-Coded Number & Ring Gauge**: Both the percentage number and circle ring gauge are independently color-coded using a 3-tier health status: Healthy (>50%: Emerald Green `0.15, 0.85, 0.55`), Warning (20%–50%: Amber/Orange `1.0, 0.60, 0.15`), and Low (≤20%: Ruby Red `1.0, 0.35, 0.35`). Because the Percentage Number and Circle Ring Gauge metrics are decoupled, their colors independently reflect their respective quota fractions (e.g. Red 15% number with a Green 85% ring). Applies across all model selections (Active, Most Depleted, Gemini, Argon, Claude).
   - **Crisp Spend Badge & Live Settings Preview**: `showMenuBarSpend` toggles a canvas-rendered spend badge (`MenuBarSpendSource`: `GCP Cloud Spend (Today)`, `Today's API Spend (All)`, `GCP Cloud Spend (Total)`) separated by a subtle 1px vertical divider and monochrome SF Symbol (`cloud.fill` or `dollarsign`) on the exact same 11pt bold rounded monospaced baseline. `SettingsTabView` includes a live **Menu Bar Preview** pill at the top.
   - **Hermetic Unit Tests**: View model unit tests must explicitly initialize `vm.selectedModelForIcon = .active` and target limits to prevent cross-test leakage via `UserDefaults.standard`.
   - **Production App Integrity Invariant**: Never leave an ad-hoc Xcode DerivedData build running on Sam's machine, and **never copy raw DerivedData builds into `/Applications/agy-usage-stats.app`**.
     - *Why*: Ad-hoc DerivedData builds have `CFBundleShortVersionString = 1.1.0`. The official GitHub rolling release is tagged with CI build sequences (e.g., `1.1.68`). When an ad-hoc build is placed in `/Applications/agy-usage-stats.app`, `UpdateChecker.swift` compares the remote version against `1.1.0` and immediately flags "New build available", prompting to overwrite local code with an older remote DMG!
     - *Proper Release Protocol*: Use `scripts/deploy_release.sh -m "<message>"`. This runs hermetic unit tests, commits, pushes to `main`, waits for GitHub Actions to build the official DMG and update the rolling `latest` release, downloads the signed/official release, terminates any running processes, installs into `/Applications/agy-usage-stats.app`, and verifies the running binary path and version.

9. **Low-Latency Quota Pipeline & Adaptive Background Polling**:
   - **Sub-300ms File Watcher Reactivity (`AgyFileWatcher`)**: Debounce delay reduced from 1500ms to 300ms so prompts and tool completions trigger quota refresh almost immediately.
   - **Fast-Path `refreshQuotaOnly()`**: Directly polls language server quota over localhost (`< 1ms` execution) without scanning `ps`, `lsof`, or reparsing history databases.
   - **Reactive Backend Settling Follow-Up**: When files change, `AgyQuotaService.clearCache()` invalidates stale cache, updates stats, and schedules a follow-up fast quota check after 1.8s to capture any delayed backend quota accounting debit.
   - **Smart Adaptive Background Polling**: Runs an adaptive loop in `AgyStatsViewModel`: polls every 4 seconds when an active Antigravity CLI session is detected (`AgyQuotaService.hasActiveSession`), backing off to 25 seconds when idle. Consumes 0.00% additional CPU with zero token burn.
   - **Instant Popover Quota Synchronization**: Opening the menu bar popover (`.onAppear`) immediately forces an asynchronous quota refresh (`forceRefresh: true`).

## Release & Deployment Workflow

To publish updates and install the official build without triggering update banners:
```bash
./scripts/deploy_release.sh -m "feat(scope): description"
```
Options:
- Default: runs unit tests, commits & pushes to `main`, monitors GitHub Actions CI, downloads official DMG, and installs into `/Applications`.
- `--local-publish`: runs unit tests, builds DMG locally with `build-dmg.sh`, publishes to GitHub `latest` release via `gh`, and installs into `/Applications`.
- `--install-latest`: skips building and installs the current GitHub `latest` release DMG into `/Applications`.

## Testing Guidelines

- Run unit tests with:
  ```bash
  xcodebuild test -project agy-usage-stats.xcodeproj -scheme agy-usage-stats -destination 'platform=macOS' -only-testing:agy-usage-statsTests CODE_SIGN_IDENTITY="-"
  ```
- **Do not run the full UI test suite (`agy_usage_statsUITests`) for routine validation** unless specifically benchmarking launch performance or visual UI regressions. UI tests repeatedly launch the app 7+ times, toggle macOS light/dark appearance, and take ~2 minutes.
- `agy_usage_statsTests` uses Swift Testing (`import Testing`) with fast, deterministic fixture-only tests that do not hit live network ports or scan disk histories. It is annotated with `@Suite(.serialized)`.


