#!/usr/bin/env bash
set -euo pipefail

# Quick local PR preview helper for Pupil Software Factory worktrees.
# Usage:
#   ./scripts/preview-pr.sh <worktree-or-alias>
#
# Examples:
#   ./scripts/preview-pr.sh journal    # Test PR #1 (Encrypted Tamper Journal)
#   ./scripts/preview-pr.sh governor   # Test PR #2 (Adaptive Vision Governor)
#   ./scripts/preview-pr.sh network    # Test PR #3 (Network Sentinel & Flap Debouncer)
#   ./scripts/preview-pr.sh lockout    # Test Wave 2 PIN Brute-Force Lockout
#   ./scripts/preview-pr.sh display    # Test Wave 2 External Display Hot-Unplug
#   ./scripts/preview-pr.sh idle       # Test Wave 2 Idle Inactivity Auto-Arm
#   ./scripts/preview-pr.sh all        # Merge all open factory branches into a preview worktree and launch
#   ./scripts/preview-pr.sh main       # Switch back to clean main dist/Pupil.app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKTREES_DIR="$(cd "${MAIN_REPO}/.." && pwd)/Pupil-worktrees"

TARGET="${1:-}"
if [[ -z "${TARGET}" ]]; then
    echo "Usage: $0 <journal|governor|network|lockout|display|idle|all|main>"
    exit 1
fi

launch_repo_app() {
    local repo_dir="$1"
    local label="$2"
    echo "==> Running unit tests in ${label} (${repo_dir})..."
    (cd "${repo_dir}" && swift test)
    echo "==> Bundling release Pupil.app for ${label}..."
    (cd "${repo_dir}" && ./scripts/bundle-app.sh release)
    echo "==> Relaunching Pupil (${label}) with Settings window..."
    killall Pupil 2>/dev/null || true
    sleep 1
    open -a "${repo_dir}/dist/Pupil.app" --args --settings
    echo "==> Now running ${label}: ${repo_dir}/dist/Pupil.app"
}

case "${TARGET}" in
    main)
        launch_repo_app "${MAIN_REPO}" "main"
        ;;
    all)
        PREVIEW_DIR="${WORKTREES_DIR}/preview-all"
        TEST_APP="${MAIN_REPO}/dist/test.pupil.app"
        if [[ ! -d "${PREVIEW_DIR}" ]]; then
            cd "${MAIN_REPO}"
            git branch -D factory/preview-all 2>/dev/null || true
            git worktree add -b factory/preview-all "${PREVIEW_DIR}" pupil/main
            cd "${PREVIEW_DIR}"
            for br in \
                feat/encrypted-tamper-journal \
                feat/adaptive-vision-governor \
                feat/network-path-tripwire \
                feat/idle-inactivity-auto-arm \
                feat/display-hotplug-sentry \
                feat/pin-brute-force-lockout
            do
                if git show-ref --verify --quiet "refs/heads/${br}"; then
                    echo "==> Merging ${br} into preview-all..."
                    git merge --no-edit "${br}"
                fi
            done
        else
            cd "${PREVIEW_DIR}"
        fi
        echo "==> Running unit tests on combined preview-all..."
        swift test
        echo "==> Bundling release app..."
        ./scripts/bundle-app.sh release
        rm -rf "${TEST_APP}"
        cp -R "${PREVIEW_DIR}/dist/Pupil.app" "${TEST_APP}"
        echo "==> Bundled combined test app at: ${TEST_APP}"
        killall Pupil 2>/dev/null || true
        sleep 1
        open -a "${TEST_APP}" --args --settings
        echo "==> Now running combined PR test app: ${TEST_APP}"
        ;;
    journal|governor|network|lockout|display|idle)
        WT_DIR="${WORKTREES_DIR}/${TARGET}"
        if [[ ! -d "${WT_DIR}" ]]; then
            echo "Error: Worktree not found at ${WT_DIR}"
            exit 1
        fi
        launch_repo_app "${WT_DIR}" "PR worktree '${TARGET}'"
        ;;
    *)
        echo "Unknown target '${TARGET}'. Choose: journal, governor, network, lockout, display, idle, all, or main"
        exit 1
        ;;
esac
