---
name: predeploy-file-prep
description: Clean up the pile of .app packages before a deploy — rotate the local _DEV test build and prune old published packages down to the two most recent. Use when asked to prep files before deploying, clean up .app files, rotate the DEV build, or tidy the repo before a release.
argument-hint: "[dev-only|no-bump]"
allowed-tools: Bash(bash *) Bash(git *) Read Glob Grep
---

# Pre-deploy file prep — rotate DEV, prune published packages

Housekeeping for the pile of `Rutter_AccountLink_*.app` files this repo
accumulates during testing. Two independent rules, applied in order:

1. **`_DEV` rotation**: the `_DEV`-suffixed `.app` is always the last version
   installed in the test tenant. Every local test build since then (VS Code
   F5 / AL:Package, untracked in git) is clutter except the newest — that one
   becomes the new `_DEV`, the old `_DEV` and the in-between builds go.
2. **Published-package pruning**: always keep exactly the two most recent
   published (AppSource) `.app` files. A new deploy build makes three exist
   briefly — prune the oldest.

Modes (`$ARGUMENTS`):
- *(empty)* — full prep: rotate DEV, build the new AppSource package, prune
  published packages down to two.
- `dev-only` — just the DEV rotation. Use when you only want to tidy local
  test builds without cutting a new AppSource package yet.
- `no-bump` — full prep, but Step 2 rebuilds the **current**
  `app_AppSource.json` version instead of bumping to the next one. For a
  redeploy of a version not yet submitted to Partner Center (a second build
  for the same PR after review comments), where bumping burns a version
  number for nothing. Never use it on a version already submitted —
  AppSource rejects a reused version.

Both scripts below default to a **dry run**: they print the exact plan
(what becomes the new `_DEV`, what gets deleted, what gets pruned) and touch
nothing. **Hard gate: run the dry run, show the user the exact plan output,
and wait for explicit confirmation before ever passing `--apply`.** Don't
infer approval from context or treat "looks routine" as consent — untracked
test-build deletion has no git history to undo. If more than a few minutes
pass between the dry run and the confirmation (disk could've changed —
another local build, a manual delete), rerun the dry run before `--apply`
rather than trusting the stale plan.

## Step 1 — Rotate the DEV build

```
bash "${CLAUDE_SKILL_DIR}/scripts/dev_rotate.sh"          # dry run — review this first
bash "${CLAUDE_SKILL_DIR}/scripts/dev_rotate.sh" --apply  # only after the plan checks out
```

Finds every untracked `Rutter_AccountLink_<version>.app` (git-status `??`),
takes the highest version (native `sort -V`, no hand parsing). On `--apply`:
renames it to `Rutter_AccountLink_<version>_DEV.app`, `git add`s it, `git rm`s
the old `_DEV` file, and deletes the other untracked stragglers in between.

- Prints `WARN` if `app.json`'s version doesn't match the promoted file's
  version. This is a hard stop for Step 2, not a note in passing: the
  invariant this whole flow relies on is **app.json's version always equals
  the current `_DEV` version** — Step 2 never touches app.json's version
  (it only swaps content in/out for the compile, then restores the exact
  prior state), so it only stays consistent if Step 1 went in clean. If this
  WARNs, stop and get the mismatch resolved (or confirmed intentional) with
  the user before continuing to Step 2.
- If it prints "No untracked test builds found", there's nothing to rotate
  — report that and move on (not an error).
- Files with any other suffix (e.g. the legacy `_PTE` one) are left alone —
  unrecognized pattern, not covered by either rule. Flag it to the user
  rather than guessing.

## Step 2 — Build the new AppSource package (skip if `dev-only`)

Confirm with the user before running this — it permanently bumps
`app_AppSource.json`'s version, and BC/AppSource never accepts a reused
version number, so an unwanted build burns one for good. (`no-bump` skips
the bump — see the mode list and the variant invocation below.)

`app.json`'s version is deliberately left untouched by this step — it stays
equal to the `_DEV` version from Step 1 (see the invariant above), not
synced to app_AppSource's new number. The two version lines (local test vs.
published) are intentionally independent.

Reuse the existing build script from the `appsource-release` skill — it
already does the exact swap-bump-package-revert dance (copy
`app_AppSource.json` over `app.json`, bump version, compile, restore
`app.json` to PTE):

```
bash "${CLAUDE_SKILL_DIR}/../appsource-release/scripts/build.sh"
```

With `no-bump`, pass the current version explicitly — `build.sh` skips the
bump when the requested version equals the current one, so this rebuilds the
same package in place:

```
bash "${CLAUDE_SKILL_DIR}/../appsource-release/scripts/build.sh" \
  "$(python3 -c 'import json;print(json.load(open("app_AppSource.json"))["version"])')"
```

The rebuilt file overwrites the existing `.app` of that version, so Step 3
has nothing new to prune.

- On success it prints `NEW_VERSION=` and `APP_FILE=`. `git add "<APP_FILE>"`
  so Step 3 can see it.
- If `alc` isn't available or the compile fails, don't retry blindly — follow
  the "Manual build fallback" in `../appsource-release/reference.md` (build
  in VS Code via `AL: Package`, then `git restore app.json` immediately),
  then resume at Step 3 with the resulting file added.

## Step 3 — Prune old published packages (skip if `dev-only`)

```
bash "${CLAUDE_SKILL_DIR}/scripts/prune_published.sh"          # dry run — review this first
bash "${CLAUDE_SKILL_DIR}/scripts/prune_published.sh" --apply  # only after the plan checks out
```

Keeps only the two highest-versioned tracked `Rutter_AccountLink_<version>.app`
files (plain name, no suffix); on `--apply`, `git rm`s the rest.

## Step 4 — Report

Summarize with `git status`: what got added/removed, the new `_DEV` file
name, the new published version if one was built, and anything flagged
(version mismatch warning, unrecognized-pattern files left untouched).

**Do not commit.** Leave everything staged — the user commits when ready, or
runs `/appsource-release` next (with the file this skill just built already
in place, answer `file_ready: true` at its Step 0 so it doesn't build again),
whose own release step will commit the new package alongside the prune.
