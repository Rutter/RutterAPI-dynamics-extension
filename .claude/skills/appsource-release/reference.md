# AppSource release — reference

Companion to SKILL.md. Click-paths, troubleshooting, and fallbacks.

## Partner Center click-path (detail)

Partner Center's UI shifts occasionally — navigate by goal, not by pixel. The
stable landmarks:

1. `https://partner.microsoft.com/dashboard/marketplace-offers/overview` — the
   "Marketplace offers" workspace lists all offers. If redirected to a
   Microsoft sign-in page (login.microsoftonline.com), pause and ask the user
   to sign in / complete MFA in the browser, then continue in the same tab.
2. Open the offer **AccountLink** (offer type "Dynamics 365 Business Central",
   publisher Rutter). Use the workspace search box if the list is long.
3. In the offer's left-hand nav, open **Properties**. Set the **App version**
   field to the new version — this is the version customers see on the
   AppSource listing detail page, and it must match the package being
   uploaded. **Save draft** before leaving the page. Don't change anything
   else on Properties (categories, industries, legal).
4. In the offer's left-hand nav, open **Technical configuration**. This page
   has two upload fields (per Microsoft docs):
   - **Extension package file** — the main `.app`. This is the only one we use.
   - **Library extension package file** — dependencies not on the marketplace.
     AccountLink has none; never touch this field.
5. The page shows the currently uploaded package. Remove/delete it, then upload
   the new signed `.app` (use the file-upload capability with the absolute
   local path). Uploads of `.app` files are known to be slow — allow several
   minutes; check for a progress indicator before concluding anything failed.
6. Click **Save draft**. Watch for inline validation errors (version must be
   higher than the published one; unsigned or malformed packages are rejected
   here or during certification).
7. Left nav → **Review and publish**. Every section should read "Complete".
   Add a short note for the certification team ("Updated extension package to
   v<NEW_VERSION>."), then click **Publish** / **Submit**.
8. The offer's Overview page should now show the publish pipeline running.
   Capture a screenshot of the confirmation for the final report.

## Publish lifecycle, sign-off, and status checks

After submission the offer's **Overview** page shows a publish lifecycle that
progresses roughly: **Automated validation → Preview creation → Publisher
signoff → Publish → Live**. Automated validation + certification usually takes
**3+ business days**; failures also arrive by email to the Partner Center
account contacts.

How to act per stage (the Step 6 state machine in SKILL.md):

- **Automated validation / certification failed**: the Overview page links to
  error details or a certification report. Read every error. Typical causes
  and responses:
  - *Signature invalid / not signed* → re-run `sign.sh`, verify, release again
    with a bumped version.
  - *AppSourceCop / code diagnostics* (AS-prefixed rules, mandatory `RTR`
    prefix, US/GB country support) → real AL code fixes; report the exact
    errors and propose the change.
  - *Version not higher than published* → bump and rerun; version numbers are
    never reusable, even after failures.
  - *Country/localization runtime errors* (fields only in the US base app —
    see README "Important notes") → reproduce via the UK company trick in the
    README, fix, rerun.
- **Publisher signoff**: Microsoft finished validation and built the preview;
  the offer waits for the publisher. Verify the pending version matches the
  expected one, then click **Go live** on the Overview page. This is the
  sign-off — after it, Microsoft runs the final publish to production, which
  can take a couple of hours. Refresh the Overview page within ~2 hours to
  confirm it completed ("Successfully published" / new version Live). If the
  final publish shows an error, capture it and report — final-publish failures
  are usually Microsoft-side; retry guidance comes from the error itself or
  Partner Center support.
- **Live**: update `RELEASES.md` (append `- Live: <date>` to the version's
  entry), commit, report.

Timers: in-session watches use background `sleep` (3600s after submit, 7200s
after Go live) and only survive while the Claude Code session stays open and
the machine is awake — they do NOT survive `claude --resume`. The durable
pattern is on-demand: `/appsource-release status` reads the expected version
from `RELEASES.md`, opens the Overview page, and acts on whatever stage it
finds. Since validation takes days, the Publisher-signoff click usually
happens on a later `status` run, not in the original release session.

### If something looks wrong

- **A submission is already in progress**: do not upload over it. Stop and
  report; a new submission generally must wait or the current one be cancelled
  deliberately by a human.
- **Unexpected page/modal/error**: screenshot, stop, report. No blind retries
  of clicks that mutate state (delete, publish).
- **Validation failure later**: read the failure email / publish status, fix
  the AL code or metadata, and rerun `/appsource-release` — the version will
  bump again, which is required anyway (BC rejects reused version numbers).

## Signing troubleshooting (from README + Azure setup)

- **Token errors** → wrong subscription: `az account set --subscription "Azure Signing Certificate"`.
- **Access denied / 403** → the signed-in user needs the
  **Code Signing Certificate Profile Signer** role on the `RutterSigning`
  account in the `azure_signing` resource group.
- **jsign missing** → `brew install jsign`; **az missing** → `brew install azure-cli`, then `az login`.
- Endpoint is `https://eus.codesigning.azure.net`, certificate profile alias
  `RutterSigning/DynamicsCertificate`.

## Manual build fallback (when scripts/build.sh can't compile)

`build.sh` needs the VS Code AL extension's `alc` binary and fresh symbols in
`.alpackages`. If it fails:

1. Ask the user to build in VS Code, exactly per README:
   - bump the version in `app_AppSource.json`
   - `cp app_AppSource.json app.json`
   - VS Code → `Ctrl+Shift+P` → **AL: Package**
   - **immediately** `git restore app.json` (golden rule: app.json stays PTE)
2. Symbol problems ("Table X is missing"): delete `.alpackages/` and run
   **AL: Download Symbols** against a Sandbox (see README "Download Symbols &
   Compile" — production doesn't expose the dev endpoint, and the launch
   config needs the tenant id set).
3. Resume the skill at Step 2 (signing) with the produced
   `Rutter_AccountLink_<version>.app`.

AppSourceCop failures (prefix `RTR` is mandatory, supported countries US/GB per
`AppSourceCop.json`) are real code issues — fix the AL source; don't strip the
analyzer to get a package out.

## Version rules

- BC caches uploaded versions: a version number can never be reused, even
  after a failed validation. Always bump.
- `app_AppSource.json` is the source of truth for the released version; the
  repo's `app.json` (PTE flavor) is for local dev and stays at its committed
  state.
- Tags follow `appsource-v<version>`; `RELEASES.md` newest-first.

## Future: fully headless alternative

If Rutter later wants this in CI without a browser or a human login, the
supported path is the **Partner Center Ingestion API** (api.partner.microsoft.com)
— the same mechanism Microsoft's AL-Go for GitHub uses for its
"Deliver to AppSource" workflow. It requires an Entra ID app registration
associated with the Partner Center account and offer-level automation setup.
The browser skill and the API path can coexist; the skill is the low-setup,
human-in-the-loop option.
