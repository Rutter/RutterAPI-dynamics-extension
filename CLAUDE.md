# AccountLink — Business Central extension

AL extension exposing custom API endpoints for Rutter's Dynamics 365 Business Central
integration. See [README.md](README.md) for what it is and how to compile and upload.

## Testing journal-line changes (MANDATORY)

**Any change to `src/codeunits/JournalLineManagement.al` requires a full green run of the
journal-line parity suite on both sandbox companies before the build ships.**

```bash
python3 testing/journal-lines/parity.py both
```

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
