#!/usr/bin/env bash
# prune_published.sh — keep only the two highest-versioned published .app
# files tracked in git (plain "Rutter_AccountLink_<version>.app", no
# _DEV/_PTE/other suffix — those are left alone, unrecognized patterns).
#
# Default is a DRY RUN — prints the plan, touches nothing. Pass --apply to
# actually git rm.
set -euo pipefail
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$REPO_ROOT"

mapfile -t PUBLISHED < <(git ls-files 'Rutter_AccountLink_*.app' \
  | grep -E '^Rutter_AccountLink_[0-9]+(\.[0-9]+){3}\.app$' || true)

if [ "${#PUBLISHED[@]}" -le 2 ]; then
  echo "Only ${#PUBLISHED[@]} published file(s) tracked — nothing to prune."
  exit 0
fi

mapfile -t SORTED < <(printf '%s\n' "${PUBLISHED[@]}" \
  | sed -E 's/^Rutter_AccountLink_(.*)\.app$/\1/' | sort -V \
  | sed -E 's/^(.*)$/Rutter_AccountLink_\1.app/')

KEEP=("${SORTED[@]: -2}")
for f in "${SORTED[@]}"; do
  keep=0
  for k in "${KEEP[@]}"; do [ "$f" = "$k" ] && keep=1; done
  if [ "$keep" -eq 0 ]; then
    if [ "$APPLY" -eq 1 ]; then
      echo "Pruning old published package: $f"
      git rm -q "$f"
    else
      echo "PLAN: git rm old published package $f"
    fi
  fi
done
[ "$APPLY" -eq 0 ] && echo "(dry run — rerun with --apply to execute)"
echo "KEPT=${KEEP[*]}"
