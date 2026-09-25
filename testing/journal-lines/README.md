# Journal-line parity suite

A/B tester for the journal-line AL blocks. Each payload is created twice in the same journal
batch — once the way the backend does it today, once through the AL action — then both lines
are read back off page 6407 and all 174 fields compared.

```bash
python3 testing/journal-lines/parity.py both     # or: usa | uae
```

**Mandatory after any change to `src/codeunits/JournalLineManagement.al`**, on both companies.

Prerequisites, how to read the output, the two sandbox tenants (and the ones never to touch),
the accepted differences, and the traps are all in
[`.claude/skills/journal-line-parity/SKILL.md`](../../.claude/skills/journal-line-parity/SKILL.md).
Read that before running — the short version is: the build must already be installed on both
environments, and rutter-backend's dev server must be up, since the suite mints a fresh BC
token per company and there is no fallback.

| File | What it is |
|---|---|
| `harness.py` | operation-agnostic: the two companies, HTTP client, fixture lookup, the diff, cleanup, version check |
| `shapes.py` | the payload catalogue and the accepted-difference map, with provenance |
| `parity.py` | the CreateLines suite — the old-way / new-way pair, drivers, entry point |

A suite for another block (UpdateLine, ReplaceLines) is a sibling of `parity.py` importing the
other two. Not CI: live tenant, real credentials, ~10 minutes.
