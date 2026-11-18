#!/usr/bin/env bash
# auto-sync-prs.sh - Software Factory Auto-Rebase Hook
set -eo pipefail

if [ -n "$AUTO_SYNC_RUNNING" ]; then
  exit 0
fi
export AUTO_SYNC_RUNNING=1

REPO_DIR="/Users/stevew/Documents/Pupil"
WORKTREE_DIR="/Users/stevew/Documents/Pupil-worktrees"

echo "🔄 Fetching latest pupil/main..."
git -C "$REPO_DIR" fetch pupil main

LATEST_MAIN=$(git -C "$REPO_DIR" rev-parse pupil/main)
echo "📍 Current main HEAD: $LATEST_MAIN"

PAIRS=(
  "siren:feat/siren-escalation-curve"
)

SYNCED_COUNT=0

for pair in "${PAIRS[@]}"; do
  wt="${pair%%:*}"
  branch="${pair##*:}"
  target_dir="$WORKTREE_DIR/$wt"

  if [ -d "$target_dir" ]; then
    cd "$target_dir"
    if [ -n "$(git status --porcelain --untracked-files=no)" ] || git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      echo "⚠️ $target_dir has uncommitted tracked changes or an in-progress merge; skipping $branch."
      continue
    fi

    git fetch pupil main "$branch" >/dev/null 2>&1 || git fetch pupil main >/dev/null 2>&1
    TARGET_MAIN=$(git rev-parse pupil/main)
    if git merge-base --is-ancestor HEAD "$TARGET_MAIN" 2>/dev/null; then
      echo "✓ $branch is already merged into main ($TARGET_MAIN)."
      continue
    fi
    MERGE_BASE=$(git merge-base HEAD "$TARGET_MAIN")

    NEEDS_MERGE=true
    if [ "$MERGE_BASE" = "$TARGET_MAIN" ]; then
      NEEDS_MERGE=false
      if git show-ref --verify --quiet "refs/remotes/pupil/$branch"; then
        AHEAD_COUNT=$(git rev-list --count "pupil/$branch..HEAD")
        if [ "$AHEAD_COUNT" -eq 0 ]; then
          echo "✓ $branch is already up to date with main ($TARGET_MAIN) and pushed."
          continue
        fi
        echo "📤 $branch is up to date with main ($TARGET_MAIN) but has $AHEAD_COUNT unpublished commit(s); retrying push..."
      else
        echo "📤 $branch is up to date with main ($TARGET_MAIN) but not yet pushed to pupil; pushing..."
      fi
    fi

    if [ "$NEEDS_MERGE" = true ]; then
      PRE_MERGE_HEAD=$(git rev-parse HEAD)
      echo "⚡ Rebasing/merging main ($TARGET_MAIN) into $branch in $target_dir..."
      if ! git merge "$TARGET_MAIN" --no-edit >/dev/null 2>&1; then
        echo "⚠️ Merge conflict detected on $branch; aborting for orchestrator resolution."
        git merge --abort >/dev/null 2>&1 || true
        continue
      fi
      echo "✅ Merged main into $branch cleanly. Running swift test..."
    else
      echo "🧪 Running swift test on unpublished commits for $branch..."
    fi

    if swift test >/dev/null 2>&1; then
      echo "🟢 All tests passed for $branch. Pushing to pupil..."
      if git push pupil "$branch" >/dev/null 2>&1; then
        echo "🚀 $branch pushed and clean on GitHub."
        SYNCED_COUNT=$((SYNCED_COUNT + 1))
      else
        echo "⚠️ Failed to push $branch to pupil; leaving local commits for retry."
      fi
    else
      if [ "$NEEDS_MERGE" = true ]; then
        echo "⚠️ Tests failed on $branch after merge; resetting to pre-merge revision $PRE_MERGE_HEAD."
        git reset --hard "$PRE_MERGE_HEAD"
      else
        echo "⚠️ Tests failed on unpublished commits for $branch; skipping push."
      fi
    fi
  fi
done

# Always synchronize and rebuild combined test.pupil.app with latest changes
if [ -d "$WORKTREE_DIR/preview-wave3" ]; then
  cd "$WORKTREE_DIR/preview-wave3"
  if [ -n "$(git status --porcelain --untracked-files=no)" ] || git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    echo "❌ $WORKTREE_DIR/preview-wave3 has uncommitted tracked changes or an in-progress merge; stopping preview assembly." >&2
    exit 1
  fi

  git fetch pupil >/dev/null 2>&1
  echo "🔨 Synchronizing combined preview branch with main and active feature branches..."
  if ! git merge pupil/main --no-edit >/dev/null 2>&1; then
    echo "❌ Failed to merge pupil/main into preview-wave3; aborting merge and stopping preview assembly." >&2
    git merge --abort >/dev/null 2>&1 || true
    exit 1
  fi

  # Merge each active branch into preview
  for pair in "${PAIRS[@]}"; do
    branch="${pair##*:}"
    if ! git merge "pupil/$branch" --no-edit >/dev/null 2>&1; then
      echo "❌ Failed to merge pupil/$branch into preview-wave3; aborting merge and stopping preview assembly." >&2
      git merge --abort >/dev/null 2>&1 || true
      exit 1
    fi
  done

  echo "🔨 Rebuilding combined dist/test.pupil.app from preview-wave3..."
  if ! ./scripts/bundle-app.sh release >/dev/null 2>&1; then
    echo "❌ Failed to bundle Pupil.app in preview-wave3; keeping existing test.pupil.app." >&2
    exit 1
  fi

  BUILT_APP="$WORKTREE_DIR/preview-wave3/dist/Pupil.app"
  if [ ! -d "$BUILT_APP" ]; then
    echo "❌ Expected bundled app missing at $BUILT_APP; keeping existing test.pupil.app." >&2
    exit 1
  fi

  mkdir -p "$REPO_DIR/dist"
  STAGED_APP="$REPO_DIR/dist/.test.pupil.app.tmp.$$"
  rm -rf "$STAGED_APP"
  if ! cp -R "$BUILT_APP" "$STAGED_APP"; then
    rm -rf "$STAGED_APP"
    echo "❌ Failed to stage $BUILT_APP; keeping existing test.pupil.app." >&2
    exit 1
  fi
  rm -rf "$REPO_DIR/dist/test.pupil.app"
  mv "$STAGED_APP" "$REPO_DIR/dist/test.pupil.app"
  echo "✨ dist/test.pupil.app rebuilt and refreshed with all latest changes!"
fi

echo "🎉 Auto-sync complete! ($SYNCED_COUNT branches updated, test.pupil.app ready)"
