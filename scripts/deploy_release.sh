#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# deploy_release.sh
# Deterministic release, build, and deploy pipeline for agy-usage-stats.
# Ensures the Production App Integrity Invariant is strictly preserved:
# 1. Runs unit tests.
# 2. Commits & pushes changes to GitHub main branch.
# 3. Waits for GitHub Actions CI to build and publish the official release (or
#    publishes directly via --local-publish).
# 4. Downloads official GitHub release DMG.
# 5. Kills any running agy-usage-stats instances (DerivedData or /Applications).
# 6. Installs official release into /Applications/agy-usage-stats.app.
# 7. Launches production app and verifies runtime integrity.
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="agy-usage-stats"
PROJECT="agy-usage-stats.xcodeproj"
SCHEME="agy-usage-stats"

MODE="ci"
COMMIT_MSG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local-publish)
            echo "❌ Error: --local-publish is strictly disallowed by the Production App Integrity Invariant."
            echo "All production DMG releases must be built, verified, and published via GitHub Actions CI."
            exit 1
            ;;
        --install-latest)
            MODE="install-latest"
            shift
            ;;
        -m|--message)
            COMMIT_MSG="$2"
            shift 2
            ;;
        *)
            if [[ -z "$COMMIT_MSG" ]]; then
                COMMIT_MSG="$1"
            fi
            shift
            ;;
    esac
done

cd "$ROOT_DIR"

if [[ "$MODE" != "install-latest" ]]; then
    # Step 1: Run hermetic unit tests
    echo "🧪 Running unit tests..."
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination 'platform=macOS,arch=arm64' \
        -only-testing:agy-usage-statsTests \
        CODE_SIGN_IDENTITY="-" \
        -quiet

    echo "✅ Unit tests passed."

    # Step 2: Check for uncommitted changes & push
    if [[ -n "$(git status --porcelain)" ]]; then
        if [[ -z "$COMMIT_MSG" ]]; then
            COMMIT_MSG="feat: update agy-usage-stats release"
        fi
        echo "📝 Staging and committing changes with message: '$COMMIT_MSG'..."
        git add -A
        git commit -m "$COMMIT_MSG"
    fi

    echo "🚀 Pushing changes to origin/main..."
    git push origin main
fi

if [[ "$MODE" == "ci" ]]; then
    echo "⏳ Waiting for GitHub Actions workflow 'Build and Upload DMG' to initiate..."
    sleep 5
    
    # Locate recent run for current HEAD commit
    HEAD_SHA="$(git rev-parse HEAD)"
    RUN_ID=""
    for i in {1..12}; do
        RUN_ID="$(gh run list --workflow=release-dmg.yml --branch=main --limit 5 --json databaseId,headSha -q ".[] | select(.headSha == \"$HEAD_SHA\") | .databaseId" | head -n 1 || true)"
        if [[ -n "$RUN_ID" ]]; then
            break
        fi
        sleep 3
    done

    if [[ -n "$RUN_ID" ]]; then
        echo "📡 Watching GitHub Actions run $RUN_ID..."
        gh run watch "$RUN_ID" --exit-status
    else
        echo "⚠️ Could not match commit SHA to GitHub run. Watching most recent workflow run..."
        LATEST_RUN_ID="$(gh run list --workflow=release-dmg.yml --branch=main --limit 1 --json databaseId -q ".[0].databaseId")"
        if [[ -n "$LATEST_RUN_ID" ]]; then
            gh run watch "$LATEST_RUN_ID" --exit-status
        fi
    fi
fi

# Step 3: Download official GitHub release DMG
TMP_DIR="$(mktemp -d /tmp/agy-release-download.XXXXXX)"
echo "⬇️ Downloading official GitHub release DMG to $TMP_DIR..."
gh release download latest --pattern "*.dmg" --dir "$TMP_DIR" --clobber

DMG_FILE="$(find "$TMP_DIR" -maxdepth 1 -name "*.dmg" | head -n 1)"
if [[ ! -f "$DMG_FILE" ]]; then
    echo "❌ Failed to download DMG from latest release."
    rm -rf "$TMP_DIR"
    exit 1
fi

# Step 4: Mount DMG
echo "📦 Mounting $DMG_FILE..."
MOUNT_DIR="/Volumes/$APP_NAME"
if [[ -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
fi

MOUNT_OUTPUT="$(hdiutil attach "$DMG_FILE" -nobrowse)"
MOUNT_POINT="$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/.*' | sed 's/[[:space:]]*$//' | head -n 1)"

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT/$APP_NAME.app" ]]; then
    echo "❌ Failed to mount DMG or app bundle not found at $MOUNT_POINT/$APP_NAME.app"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Step 5: Terminate any running agy-usage-stats processes
echo "🛑 Terminating running agy-usage-stats processes..."
killall -9 "$APP_NAME" 2>/dev/null || true
pkill -9 -f "$APP_NAME" 2>/dev/null || true
sleep 1

# Step 6: Install official release into /Applications
echo "🚚 Installing $MOUNT_POINT/$APP_NAME.app into /Applications/$APP_NAME.app..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$MOUNT_POINT/$APP_NAME.app" "/Applications/"

# Step 7: Record release metadata in UserDefaults to guarantee zero false update loops
RELEASE_META="$(gh release view latest --json publishedAt,name 2>/dev/null || echo "{}")"
PUBLISHED_ISO="$(echo "$RELEASE_META" | jq -r '.publishedAt // empty' 2>/dev/null || echo "")"
RELEASE_TITLE="$(echo "$RELEASE_META" | jq -r '.name // empty' 2>/dev/null || echo "")"

if [[ -n "$PUBLISHED_ISO" ]]; then
    PUBLISHED_TS="$(python3 -c "import datetime; print(int(datetime.datetime.fromisoformat('$PUBLISHED_ISO'.replace('Z', '+00:00')).timestamp()))" 2>/dev/null || echo "")"
    if [[ -n "$PUBLISHED_TS" ]]; then
        echo "📌 Recording lastInstalledRollingTimestamp=$PUBLISHED_TS in UserDefaults..."
        defaults write luminoslabs.agy-usage-stats lastInstalledRollingTimestamp -float "$PUBLISHED_TS"
    fi
fi
if [[ -n "$RELEASE_TITLE" ]]; then
    defaults write luminoslabs.agy-usage-stats lastInstalledReleaseVersion "$RELEASE_TITLE"
fi

# Step 8: Clean up DMG mount and temp dir
hdiutil detach "$MOUNT_POINT" -quiet
rm -rf "$TMP_DIR"

# Step 9: Launch official production app
echo "🚀 Launching /Applications/$APP_NAME.app..."
open "/Applications/$APP_NAME.app"
sleep 2

# Step 10: Verify running process and version
RUNNING_BIN="$(ps aux | grep -i "/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME" | grep -v grep | awk '{print $NF}' || true)"
INSTALLED_VER="$(defaults read "/Applications/$APP_NAME.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")"
LATEST_GH_VER="$(gh release view latest --json name -q '.name' 2>/dev/null || echo "unknown")"

echo ""
echo "═════════════════════════════════════════════════════════════════════"
echo "  Production App Integrity Verification:"
echo "  • Installed Bundle Version: $INSTALLED_VER"
echo "  • Official GitHub Release:  $LATEST_GH_VER"
echo "  • Running Executable:      $RUNNING_BIN"
echo "═════════════════════════════════════════════════════════════════════"

if [[ -z "$RUNNING_BIN" ]]; then
    echo "❌ Error: Production app does not appear to be running."
    exit 1
fi

echo "✅ Production App Integrity Invariant verified. App is running cleanly from /Applications."
