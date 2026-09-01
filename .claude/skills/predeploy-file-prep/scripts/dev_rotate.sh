#!/usr/bin/env bash
# dev_rotate.sh — rotate the local _DEV test package before a deploy.
#
# Promotes the highest-versioned untracked test .app (built locally via
# VS Code F5 / AL:Package during sandbox testing) to the new *_DEV.app,
# removes the old _DEV file, and deletes any other untracked test builds
# created in between (e.g. .6/.7 when .8 is the latest).
#
# Default is a DRY RUN — prints the plan, touches nothing. Pass --apply to
# actually rename/delete/git-rm. Untracked-file deletion has no git history
# to recover from, so always review the plan first.
set -euo pipefail
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$REPO_ROOT"

# read -r loops, not mapfile: macOS ships bash 3.2, where mapfile doesn't exist.
OLD_DEV=()
while IFS= read -r line; do OLD_DEV+=("$line"); done < <(git ls-files 'Rutter_AccountLink_*_DEV.app')
[ "${#OLD_DEV[@]}" -le 1 ] || { echo "ERROR: multiple _DEV files tracked: ${OLD_DEV[*]}" >&2; exit 1; }
OLD_DEV_FILE="${OLD_DEV[0]:-}"

CANDIDATES=()
while IFS= read -r line; do CANDIDATES+=("$line"); done < <(git status --porcelain --untracked-files=all -- 'Rutter_AccountLink_*.app' \
  | awk '{print $2}' | grep -E '^Rutter_AccountLink_[0-9]+(\.[0-9]+){3}\.app$' || true)

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  echo "No untracked test builds found — nothing to rotate."
  echo "OLD_DEV=${OLD_DEV_FILE:-none}"
  exit 0
fi

# highest version wins (native version-sort, no custom parsing)
NEW_DEV_VERSION="$(printf '%s\n' "${CANDIDATES[@]}" \
  | sed -E 's/^Rutter_AccountLink_(.*)\.app$/\1/' | sort -V | tail -1)"
NEW_DEV_SRC="Rutter_AccountLink_${NEW_DEV_VERSION}.app"

APP_JSON_VERSION="$(python3 -c 'import json;print(json.load(open("app.json"))["version"])')"
if [ "$APP_JSON_VERSION" != "$NEW_DEV_VERSION" ]; then
  echo "WARN: app.json version ($APP_JSON_VERSION) != highest local test build ($NEW_DEV_VERSION)." >&2
fi

DEV_TARGET="Rutter_AccountLink_${NEW_DEV_VERSION}_DEV.app"

for f in "${CANDIDATES[@]}"; do
  [ "$f" = "$NEW_DEV_SRC" ] && continue
  if [ "$APPLY" -eq 1 ]; then
    echo "Removing stray test build: $f"
    rm -f "$f"
  else
    echo "PLAN: delete stray test build $f"
  fi
done

if [ "$APPLY" -eq 1 ]; then
  mv "$NEW_DEV_SRC" "$DEV_TARGET"
  git add "$DEV_TARGET"
  if [ -n "$OLD_DEV_FILE" ] && [ "$OLD_DEV_FILE" != "$DEV_TARGET" ]; then
    git rm -q "$OLD_DEV_FILE"
  fi
else
  echo "PLAN: promote $NEW_DEV_SRC -> $DEV_TARGET"
  [ -n "$OLD_DEV_FILE" ] && [ "$OLD_DEV_FILE" != "$DEV_TARGET" ] && echo "PLAN: git rm old DEV $OLD_DEV_FILE"
  echo "(dry run — rerun with --apply to execute)"
fi

echo "OLD_DEV=${OLD_DEV_FILE:-none}"
echo "NEW_DEV=$DEV_TARGET"
