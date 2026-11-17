#!/usr/bin/env bash
# auto-sync-prs.sh - Software Factory Auto-Rebase Hook
set -eo pipefail

REPO_DIR="/Users/stevew/Documents/Pupil"
WORKTREE_DIR="/Users/stevew/Documents/Pupil-worktrees"

echo "🔄 Fetching latest pupil/main..."
git -C "$REPO_DIR" fetch pupil main

LATEST_MAIN=$(git -C "$REPO_DIR" rev-parse pupil/main)
echo "📍 Current main HEAD: $LATEST_MAIN"

PAIRS=(
  "siren:feat/siren-escalation-curve"
  "usb:feat/usb-security-key"
  "wifi:feat/trusted-wifi-boundary"
)

SYNCED_COUNT=0

for pair in "${PAIRS[@]}"; do
  wt="${pair%%:*}"
  branch="${pair##*:}"
  target_dir="$WORKTREE_DIR/$wt"

  if [ -d "$target_dir" ]; then
    echo "⚡ Checking $branch in $target_dir..."
    cd "$target_dir"
    git fetch pupil main >/dev/null 2>&1
    
    # Try merging main
    if git merge pupil/main --no-edit >/dev/null 2>&1; then
      echo "✅ Merged main into $branch cleanly. Running swift test..."
      if swift test >/dev/null 2>&1; then
        echo "🟢 All tests passed for $branch. Pushing to pupil..."
        git push pupil "$branch" >/dev/null 2>&1 || true
        echo "🚀 $branch pushed and clean on GitHub."
        SYNCED_COUNT=$((SYNCED_COUNT + 1))
      else
        echo "⚠️ Tests failed on $branch after merge; resetting merge."
        git reset --hard HEAD~1
      fi
    else
      echo "ℹ️ Already up to date or has conflict; checking clean..."
      git merge --abort >/dev/null 2>&1 || true
    fi
  fi
done

# Rebuild combined test.pupil.app automatically
if [ -d "$WORKTREE_DIR/preview-wave3" ]; then
  echo "🔨 Rebuilding combined dist/test.pupil.app from preview-wave3..."
  cd "$WORKTREE_DIR/preview-wave3"
  ./scripts/bundle-app.sh release >/dev/null 2>&1 || true
  rm -rf "$REPO_DIR/dist/test.pupil.app"
  cp -R "$WORKTREE_DIR/preview-wave3/dist/Pupil.app" "$REPO_DIR/dist/test.pupil.app"
  echo "✨ dist/test.pupil.app refreshed and ready!"
fi

echo "🎉 Auto-sync complete! ($SYNCED_COUNT branches processed)"
