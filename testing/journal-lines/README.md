# Journal-line parity suite

A/B tester for the journal-line AL blocks. Each payload is created twice in the same journal
batch — once the way the backend does it today, once through the AL action — then both lines
are read back off page 6407 and all 174 fields compared.

```bash
testing/journal-lines/run_all.sh <log dir>             # both suites, both companies
python3 testing/journal-lines/parity.py usa            # CreateLines — or: uae | both
python3 testing/journal-lines/update_parity.py usa     # UpdateLines — or: uae | both
```

**Mandatory after any change to `src/codeunits/JournalLineManagement.al`**, on both companies.

Prerequisites, how to read the output, the declared test connections (and the rule that nothing else may be used),
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
| `update_shapes.py` | the UpdateLines catalogue: starting lines, updates, BC rule cases, failure cases |
| `update_parity.py` | the UpdateLines suite, same structure as `parity.py`, ending with the same-value sweep |
| `run_all.sh` | both suites on both companies, companies in parallel |

A suite for another block (ReplaceLines) is a sibling of these importing `harness.py`. Not CI:
live tenant, real credentials.
