#!/usr/bin/env bash
# build.sh — compile the AppSource-flavored .app for AccountLink.
#
# Usage: build.sh [NEW_VERSION]
#   NEW_VERSION  optional, e.g. 22.3.0.16. If omitted, the last segment of the
#                version in app_AppSource.json is incremented.
#
# What it does (mirrors the manual process in README.md, but crash-safe):
#   1. bump version in app_AppSource.json
#   2. back up app.json (PTE state), copy app_AppSource.json over it
#   3. compile with alc (AL compiler from the VS Code AL extension) with
#      AppSourceCop enabled (matches .vscode/settings.json)
#   4. ALWAYS restore app.json via exit trap; on failure also revert the bump
#
# Prints on success:  NEW_VERSION=<v>  and  APP_FILE=<path>
set -euo pipefail

# --- locate repo root (script lives in .claude/skills/appsource-release/scripts) ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$REPO_ROOT"
[ -f app_AppSource.json ] || { echo "ERROR: app_AppSource.json not found in $REPO_ROOT" >&2; exit 1; }

PTE_BACKUP="app.json.pte-backup"
APPSOURCE_BACKUP="app_AppSource.json.orig-backup"

if [ -f "$PTE_BACKUP" ] || [ -f "$APPSOURCE_BACKUP" ]; then
  echo "ERROR: stale backup file(s) from a crashed run exist ($PTE_BACKUP / $APPSOURCE_BACKUP)." >&2
  echo "Inspect them: app.json should be PTE (id ...2301). Restore manually, delete backups, retry." >&2
  exit 1
fi

# --- sanity: app.json must currently be in PTE state (golden rule) ---
if ! grep -q '"id": "53e5d980-b185-42a1-a5a1-ad9cd5712301"' app.json; then
  echo "ERROR: app.json is NOT in PTE state (expected id ...2301). Run 'git restore app.json' first." >&2
  exit 1
fi

# --- compute new version ---
CUR_VERSION="$(python3 -c 'import json;print(json.load(open("app_AppSource.json"))["version"])')"
if [ "${1:-}" != "" ]; then
  NEW_VERSION="$1"
  echo "$NEW_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    || { echo "ERROR: version must look like 22.3.0.16 (got: $NEW_VERSION)" >&2; exit 1; }
else
  NEW_VERSION="$(python3 -c "
v='$CUR_VERSION'.split('.'); v[-1]=str(int(v[-1])+1); print('.'.join(v))")"
fi
echo "Building AppSource package: $CUR_VERSION -> $NEW_VERSION"

# --- backups + exit trap: restore app.json ALWAYS; revert bump on failure ---
cp app.json "$PTE_BACKUP"
cp app_AppSource.json "$APPSOURCE_BACKUP"
SUCCESS=0
restore() {
  if [ -f "$PTE_BACKUP" ]; then
    mv -f "$PTE_BACKUP" app.json
    echo "app.json restored to PTE state."
  fi
  if [ "$SUCCESS" -ne 1 ] && [ -f "$APPSOURCE_BACKUP" ]; then
    mv -f "$APPSOURCE_BACKUP" app_AppSource.json
    echo "app_AppSource.json version bump reverted (build failed)."
  fi
  rm -f "$APPSOURCE_BACKUP"
}
trap restore EXIT

# --- bump version in app_AppSource.json (only the version line) ---
if [ "$NEW_VERSION" != "$CUR_VERSION" ]; then
  python3 - "$NEW_VERSION" <<'PYEOF'
import re, sys
new = sys.argv[1]
p = "app_AppSource.json"
s = open(p).read()
s2, n = re.subn(r'("version"\s*:\s*")[^"]+(")', r'\g<1>' + new + r'\g<2>', s, count=1)
assert n == 1, "version field not found"
open(p, "w").write(s2)
PYEOF
fi

# --- swap: AppSource config becomes app.json for the compile ---
cp app_AppSource.json app.json

# --- locate the AL compiler from the newest installed VS Code AL extension ---
AL_EXT="$(ls -td "$HOME/.vscode/extensions"/ms-dynamics-smb.al-*/ 2>/dev/null | head -1 || true)"
AL_EXT="${AL_EXT%/}"
[ -n "$AL_EXT" ] || { echo "ERROR: AL Language extension not found under ~/.vscode/extensions (install it in VS Code)." >&2; exit 1; }
# Pick candidates by actual host OS/arch first — a stale binary for another
# platform can exist on disk (e.g. a synced/shared extensions dir) and would
# otherwise be picked by file-existence alone, failing with "Exec format error".
case "$(uname -s)" in
  Darwin) case "$(uname -m)" in
            arm64) CANDIDATES=("$AL_EXT/bin/darwin/arm64/alc" "$AL_EXT/bin/darwin/alc") ;;
            *)     CANDIDATES=("$AL_EXT/bin/darwin/alc" "$AL_EXT/bin/darwin/arm64/alc") ;;
          esac ;;
  Linux)  CANDIDATES=("$AL_EXT/bin/linux/alc") ;;
  *)      CANDIDATES=("$AL_EXT/bin/linux/alc" "$AL_EXT/bin/darwin/alc" "$AL_EXT/bin/darwin/arm64/alc") ;;
esac
ALC=""
for cand in "${CANDIDATES[@]}"; do
  [ -f "$cand" ] && { ALC="$cand"; break; }
done
[ -n "$ALC" ] || { echo "ERROR: alc binary not found inside $AL_EXT for $(uname -s)/$(uname -m)" >&2; exit 1; }
chmod +x "$ALC" 2>/dev/null || true

# --- symbols must already be downloaded (VS Code: AL: Download Symbols) ---
if [ ! -d .alpackages ] || [ -z "$(ls -A .alpackages 2>/dev/null)" ]; then
  echo "ERROR: .alpackages is missing/empty. In VS Code run 'AL: Download Symbols' first (needs a Sandbox, see README)." >&2
  exit 1
fi

# --- AppSourceCop, matching .vscode/settings.json ("al.codeAnalyzers": ["${AppSourceCop}"]) ---
COP_DLL="$(find "$AL_EXT/bin" -name 'Microsoft.Dynamics.Nav.AppSourceCop.dll' 2>/dev/null | head -1 || true)"

OUT_FILE="Rutter_AccountLink_${NEW_VERSION}.app"
echo "Compiling with: $ALC"
if [ -n "$COP_DLL" ]; then
  "$ALC" /project:"$REPO_ROOT" /packagecachepath:"$REPO_ROOT/.alpackages" /out:"$REPO_ROOT/$OUT_FILE" "/analyzer:$COP_DLL"
else
  echo "WARN: AppSourceCop.dll not found — compiling WITHOUT AppSourceCop. Partner Center validation may catch issues locally missed." >&2
  "$ALC" /project:"$REPO_ROOT" /packagecachepath:"$REPO_ROOT/.alpackages" /out:"$REPO_ROOT/$OUT_FILE"
fi

[ -f "$OUT_FILE" ] || { echo "ERROR: compile reported success but $OUT_FILE not found." >&2; exit 1; }
SUCCESS=1

echo ""
echo "NEW_VERSION=$NEW_VERSION"
echo "APP_FILE=$REPO_ROOT/$OUT_FILE"
