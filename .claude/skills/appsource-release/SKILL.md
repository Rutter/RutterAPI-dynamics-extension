---
name: appsource-release
description: Build, sign, and upload a new version of the AccountLink extension to Microsoft AppSource, or check/troubleshoot a submission's validation status. Use when asked to release, ship, publish, or upload the Business Central extension or .app package to AppSource / Microsoft Partner Center, to sign the .app package, or to check on an AppSource submission.
argument-hint: "[version | status]"
allowed-tools: Bash(bash *) Bash(jsign *) Bash(az account *) Bash(git tag *) Bash(git add *) Bash(git commit *) Bash(git push *) Bash(git log *) Bash(git status *) Bash(sleep *) Read Glob Grep
---

# AppSource Release — build, sign, upload, watch

End-to-end release of the AccountLink Business Central extension: compile the
AppSource-flavored `.app`, code-sign it with Azure Trusted Signing, update the
Microsoft Partner Center offer through the browser (App version + package),
submit for validation, record the release, then check back on validation.
Runs fully automatically — no confirmation gates — but STOP immediately and
report if any step errors. Never guess through a failure.

## Modes (`$ARGUMENTS`)

- *(empty)* — full release; the last segment of the version in
  `app_AppSource.json` is auto-incremented.
- `22.3.0.16` (a version) — full release with that exact version.
- `status` — skip straight to **Step 6: Check validation status** for the most
  recently submitted version (top entry of `RELEASES.md`). Use this any time
  someone asks "did the AppSource upload go through?" — it is always safe to
  run, from any session.

Detailed click-paths, troubleshooting, and fallbacks: `${CLAUDE_SKILL_DIR}/reference.md`.

## Step 0 — Preflight

1. **Browser bridge**: the Partner Center upload needs the Claude in Chrome
   tools (`mcp__claude-in-chrome__*`). If they are not available in this
   session, ask the user to run `/chrome` (or restart with `claude --chrome`)
   and stop until they have.
2. **Repo state**: run `git status` from the repo root. Uncommitted changes to
   `src/` or `app_AppSource.json` are fine to release only if the user intended
   them — mention anything surprising.
3. **Golden rule check**: `app.json` must be in PTE state — its `id` must end
   in `...2301` and its `idRanges` must start at `71692`. If it contains the
   AppSource id (`...2307`) it was left swapped by a previous build; restore it
   (`git restore app.json`) before continuing and tell the user.
4. Confirm `jsign` exists (`command -v jsign`) and Azure CLI is logged in
   (`az account show`). If not: `brew install jsign` / `az login` — the login
   must be done by the user, so pause and ask if needed.

## Step 1 — Build the AppSource package

```
bash "${CLAUDE_SKILL_DIR}/scripts/build.sh" $ARGUMENTS
```

The script does the whole swap dance safely: bumps the version in
`app_AppSource.json`, copies it over `app.json`, compiles with the AL compiler
(`alc`) with AppSourceCop enabled, and **always restores `app.json` to its PTE
state via an exit trap — even on failure**. On failure it also reverts the
version bump so a rerun does not double-bump.

- On success it prints `NEW_VERSION=` and `APP_FILE=` — use these downstream.
- Verify afterwards: the `.app` file exists, and `app.json` is back in PTE
  state (id `...2301`).
- If the script fails (alc missing, stale symbols, AppSourceCop errors), see
  "Manual build fallback" in reference.md: the user builds in VS Code instead,
  then resume from Step 2 with the resulting file. AppSourceCop errors are code
  problems — report them, do not bypass the analyzer.

## Step 2 — Sign the package

```
bash "${CLAUDE_SKILL_DIR}/scripts/sign.sh" "<APP_FILE>"
```

Signs with jsign against Azure Trusted Signing (`RutterSigning/DynamicsCertificate`)
and verifies by extracting the signature. Success = it prints
`SIGNATURE_VERIFIED=1`. Token/permission errors → troubleshooting section in
reference.md. Never upload an unverified file.

## Step 3 — Update the offer in Partner Center (browser)

Follow the click-path in reference.md. The order below matches Rutter's
established process — keep it:

1. Get browser tab context first, then open a new tab at
   `https://partner.microsoft.com/dashboard/marketplace-offers/overview`.
2. If a Microsoft sign-in page appears (2FA account), pause and ask the user
   to complete login/MFA in the browser, then continue.
3. Open the offer named **AccountLink** (publisher Rutter, type Dynamics 365
   Business Central). If the offer already shows a submission in progress,
   STOP and report instead of stacking a new one.
4. Left nav → **Properties**: set the **App version** field to
   `<NEW_VERSION>` (this is the version customers see on the AppSource
   listing). **Save draft**.
5. Left nav → **Technical configuration**: under **Extension package file**,
   remove the currently uploaded `.app`, then upload the newly signed file
   using its absolute path. Uploads can take several minutes — poll patiently,
   do not assume failure early. (Never touch **Library extension package
   file**.)
6. **Save draft** and confirm the page reports no errors.
7. Go to **Review and publish**: all sections should show Complete. In notes
   for certification write: `Updated extension package to v<NEW_VERSION>.`
   Then click **Publish** (or **Submit**).
8. Confirm the offer status shows the submission is in progress (automated
   validation), e.g. "Publish in progress".

Hard rules for the browser phase: touch nothing on the offer except the App
version property, the extension package upload, and the certification notes;
if a page looks unexpected or shows an error, take a screenshot, stop, and
report — never retry destructive clicks blindly.

## Step 4 — Record the release

Only after a successful submission:

1. Append to `RELEASES.md` (create it if missing), newest entry on top:

   ```markdown
   ## v<NEW_VERSION> — <YYYY-MM-DD>
   - File: <APP_FILE> (signed, Azure Trusted Signing)
   - Submitted to Partner Center for automated validation (~3+ business days)
   - Changes: <one line, summarized from git log since the previous appsource-v* tag>
   ```

2. Commit and tag:

   ```
   git add app_AppSource.json RELEASES.md "<APP_FILE>"
   git commit -m "Release AccountLink v<NEW_VERSION> to AppSource"
   git tag appsource-v<NEW_VERSION>
   git push && git push origin appsource-v<NEW_VERSION>
   ```

   If push is rejected (protected branch), leave the commit + tag local and
   tell the user to push via their normal PR flow.

## Step 5 — Post-submit watch (1 hour)

Early failures (package rejected, signature problems, validation tripping
immediately) usually surface within the first hour. After Step 4:

1. Start a background timer: `sleep 3600 && echo APPSOURCE_CHECK_DUE`
   (run in the background — do not block on it).
2. Tell the user you'll check the submission in ~1 hour, and that this only
   works while this Claude Code session stays open and the Mac stays awake —
   background timers do not survive session resume. If the session won't stay
   open, anyone can run `/appsource-release status` later instead; it picks up
   from wherever the offer actually is.
3. When the timer fires, run Step 6.

## Step 6 — Check status & act (also the `status` mode entry point)

Open the offer's **Overview** page in Partner Center (login pause rules from
Step 3 apply) and read the publish lifecycle. Act on whichever stage the offer
is in — this is a state machine, safe to run repeatedly:

- **Failure shown** (automated validation or certification errors): open the
  error details / view the report, read every error, and troubleshoot per
  reference.md. Code/AppSourceCop issues → report with the exact errors and
  propose the AL fix; signing issues → re-sign and rerun the release (version
  must bump — BC never accepts a reused version). Update the `RELEASES.md`
  entry with the failure.
- **Still in progress** (automated validation / preview creation): report the
  stage. If this session is staying open, schedule another background check
  (validation typically takes 3+ business days, so checking hourly is noise —
  once more in a few hours, then rely on `status` runs).
- **Publisher signoff reached**: verify the pending version shown matches the
  released `<NEW_VERSION>`, then sign off — click **Go live** — to start the
  final publish. Then start a background timer for **2 hours**
  (`sleep 7200 && echo APPSOURCE_GOLIVE_CHECK_DUE`); when it fires, refresh
  the Overview page and confirm the publish succeeded (offer shows the new
  version live / "Successfully published"). Same session-lifetime caveat as
  Step 5 — `/appsource-release status` is the fallback.
- **Live**: confirm the listed version, append `- Live: <YYYY-MM-DD>` to the
  release's entry in `RELEASES.md` (commit + push), and report success.

`status` mode: read the expected version from the top entry of `RELEASES.md`,
then run this step directly (skip Steps 0–5, except the browser-bridge check).

## Step 7 — Report

One short summary: version, signed file name, current lifecycle stage, what
was clicked (submit / Go live), and what's being watched or should be checked
later with `/appsource-release status`. Failures arrive via Partner Center and
email too. If anything was left incomplete (e.g. unpushed commit), say so
explicitly.

## Failure handling

Whatever step fails: stop, report exactly what completed and what didn't, and
state the repo condition — especially whether `app.json` is back in PTE state
and whether `app_AppSource.json` kept a version bump. The scripts are designed
so a rerun of `/appsource-release` after a fix is always safe.
