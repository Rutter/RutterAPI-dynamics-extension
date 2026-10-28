# AccountLink — Business Central extension

AL extension exposing custom API endpoints for Rutter's Dynamics 365 Business Central
integration. See [README.md](README.md) for what it is and how to compile and upload.

## Testing journal-line changes (MANDATORY)

**Any change to `CreateLines`, `UpdateLines` or the field logic they share in
`src/codeunits/JournalLineManagement.al` requires a full green run of both journal-line parity
suites on both sandbox companies before the build ships.** DeleteLines and PostLines have no
suite yet.

```bash
testing/journal-lines/run_all.sh <log dir>
```

**A new block never changes how a shipped block behaves**, even to fix a bug in code they
share. Scope the change to the new block (e.g. behind `MatchPatchRules`) and fix the shipped
block separately, with evidence and its own parity run.

Load the `journal-line-parity` skill, or read
[`.claude/skills/journal-line-parity/SKILL.md`](.claude/skills/journal-line-parity/SKILL.md),
before running it — it holds the prerequisites, the declared test connections it may run
against (never a customer connection), how to read the output, and the accepted differences.

Machine-specific paths the tooling needs, such as where rutter-backend is checked out, live
in `CLAUDE.local.md` (gitignored). Ask rather than guess, and record the answer there.

## Versioning

BC caches uploaded versions: once a version is installed, that number is spent and the next
upload must be higher. `app.json` is the PTE/local test version and must always equal the
current `_DEV` package; `app_AppSource.json` is the published version and moves independently.

AppSource releases are their own commit **after** the feature PR merges — never build a
marketplace package from an unmerged branch. Use the `appsource-release` skill.

## Other skills

- `predeploy-file-prep` — rotate the `_DEV` build, prune old published packages.
- `appsource-release` — build, sign, upload to Partner Center, record the release.
