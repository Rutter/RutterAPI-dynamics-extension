---
name: journal-line-parity
description: Run the journal-line parity suite against both sandbox companies to verify a journal-line AL block behaves exactly like the endpoint it replaces. MANDATORY after any change to the RTR Journal Line Mgt codeunit. Use when testing or verifying CreateLines / DeleteLines / PostLines, after building and installing a new AccountLink version, or when asked whether a journal-line change is safe to ship.
argument-hint: "[usa|uae|both]"
allowed-tools: Bash(python3 *) Bash(curl *) Bash(yarn *) Bash(pkill *) Bash(ps *) Read Glob Grep
---

# Journal-line parity suite

Creates every payload twice in the same journal batch — once the way the backend does it
today (POST `workflowGenJournalLines`, then the bank / VAT-posting-group / tax-amount
PATCHes), once through the AL action — reads both lines back off page 6407 and compares
**all 174 fields**. A difference is either a deliberate fix or a regression; there is no
third option.

On FND-3323 it caught five real bugs that code review did not, two of which appeared on only
one of the two companies.

## Caveat: this measures against a moving target

The "old way" half is a **hand-written replica** of rutter-backend's
`src/platformization/platforms/dynamics_365/strategies/createJournalLines.ts` as it stands
*before* the swap to the AL block. It is not that code, it mirrors it. Two consequences:

- **If that file's POST/PATCH sequence changes, the replica drifts** and the comparison
  quietly stops meaning anything while still reporting green. Re-read `legacy_create` against
  the real strategy whenever the backend side moves.
- **Once the swap rolls out (FND-3325 onward) the legacy path stops being production**, and
  A/B against it is measuring against a fossil. The suite is at its most useful right now,
  while both paths are live and the AL block is new. After the swap, convert it to golden
  snapshots — record the fields per shape once and assert against them — so it survives as a
  plain regression test instead of quietly rotting.

## The rule

**Any change to `src/codeunits/JournalLineManagement.al` requires a full green run on both
companies before the build ships.** Not a subset, not one company. If you changed the
codeunit and have not run this, the change is not verified.

(Current scope is the CreateLines suite. Widen this rule as the other blocks get suites.)

## The declared test connections

`CONFIG` in `harness.py` is the allowlist. These are the connections currently declared:

| Key | Company | Environment | Company id | Rutter item |
|---|---|---|---|---|
| `usa` | CRONUS USA, Inc. | `Production` | `2887748d-9c8e-ee11-be3f-6045bde9b4bf` | `1912f593-6087-4c8d-aaf0-3615cbdd414e` |
| `uae` | CRONUS UAE 2 | `taxes_test` | `af651e34-b68a-f111-8072-6045bd7a8d46` | **varies per machine — see below** |

**The UAE item id is not the same for everyone.** That connection was made by logging in on
one person's machine, so the item row lives in *their* local dev DB. On another machine that
id does not exist and the token mint will fail. To get your own, either connect CRONUS UAE 2
through Rutter Link locally, or take the item id from prod if a connection to that company
already exists there. Then record it in `CLAUDE.local.md` at the repo root:

```markdown
uae item: <item-id>
```

The harness reads it from there (or from `RUTTER_ITEM_ID`) and prints instructions if it is
missing. The company id above does not vary — that is the Business Central company, which is
the same for everyone; only the Rutter connection to it is local.

**Run against declared connections only. Never a customer connection.** The suite writes
journal lines into a live Business Central company; on a customer's tenant that is their
data, not test data. Anything not in `CONFIG` is assumed to be a customer connection.

Adding an entry to `CONFIG` is the act of declaring a connection safe to write to — do it
only for a company we own, and confirm with the user before adding one. Company names are
not evidence: several customer realms carry CRONUS-style demo names.

**Both companies, every time.** They are not redundant: `taxGroupCode` diverged only on USA,
`vatCalculationType` only on the VAT company, and a bank account carrying a currency (USA's
`B010`) rejects lines that one without a currency accepts.

## Before running

1. **The build under test must be installed on both environments.** The suite checks the
   version and refuses to run below `MIN_EXTENSION_VERSION` in `harness.py` (currently
   22.5.0.29 — bump it when a new block ships). It cannot tell you whether *your* build is
   the one installed, only that something recent enough is. Installing is manual: build in
   VS Code, upload through Extension Management on each environment.
2. **rutter-backend's dev server must be running**, so the suite can mint its own BC tokens
   from `/admin-ops/blessed-postman-platform-setup/<item_id>`. BC tokens expire after about
   an hour, so this is the difference between running the suite and hand-refreshing tokens.

   The path to that repo is not hardcoded anywhere. If you do not already know it, **ask the
   user, then record it in `CLAUDE.local.md` at the root of this repo** so the next session
   does not ask again:

   ```markdown
   # Local paths
   rutter-backend: /path/to/rutter-backend
   ```

   Then:
   ```bash
   cd <rutter-backend> && yarn dev:web        # wait for http://localhost:$PORT/health
   ```
   Stop the server afterwards if you started it. There is **no token fallback** — a BC token
   lasts about an hour, so a saved one is a stale one. Without the server the suite exits and
   tells you to start it. If it listens on a non-default port, pass `PORT=<port>`.

## Run

```bash
python3 testing/journal-lines/parity.py both     # or: usa | uae
```

Takes about 10 minutes for both companies. Run it in the background and read the output file
rather than blocking.

## Reading the output

| Line | Meaning | Action |
|---|---|---|
| `PASS  <shape>` | identical across all 174 fields | none |
| `PASS  <shape>  (known: …)` | only accepted differences | none — see below |
| `DIFF  <shape>` | unexpected field difference | **a finding.** Diagnose before shipping |
| `ERROR <shape>` | one of the two paths threw | read the BC message; usually a real rejection |
| `FAIL  <failure case>` | a payload that must be rejected was accepted, or left rows behind | **a finding** — the transaction guarantee is broken |

The run ends with a `PASS`/`FAIL` per company and exits non-zero on any failure.

## Accepted differences — do not "fix" these

`ACCEPTED` in `shapes.py` lists fields allowed to differ per shape. Currently one entry, for
`bal account pair`:

- **`description`** — the old path overwrites it with the balancing account's name; the AL
  block keeps what the caller sent. Page 6407 applies `accountId` near the end, so the old
  path's `Account No.` is still blank when the bal account validates, and BC's
  `ReplaceDescription()` only overwrites in that state. Reproducing it means reintroducing
  the mismatched in-between state the block exists to remove.
- **`balanceLcy`** — same cause; a display-only running balance that is never posted.

Add an entry only with the reason written down. An unexplained entry is a hidden regression.

## Traps

- **BC tokens last about an hour.** Enough for one full run, not two. A mid-run 401 kills the
  company being tested; re-run it.
- **A crashed run leaves lines behind** — cleanup is the last step. Before re-running, list
  the batch and delete them, or the failure-case row counts are meaningless:
  ```bash
  # list, then feed the ids to Microsoft.NAV.deleteLines on the same journalBatchActions id
  GET {odata}/workflowGenJournalLines?$filter=journalBatchName eq 'DEFAULT' and journalTemplateName eq 'GENERAL'
  ```
- **`pkill -f "yarn dev:web"` leaves the `ts-node src/index.ts` child holding the port.** Kill
  that pid too, and confirm with `curl localhost:$PORT/health`.

## Extending it

- **New shapes** come from real traffic, never invention. The Datadog query:
  ```
  env:production "Creating dimensionSetLines for journalLines"
  extra_fields: ["journalLinesRequest"]
  ```
  That attribute holds the complete request body the backend sent. Retarget it to the sandbox
  accounts and add it to `shapes()` with a comment naming its source.
- **A new operation** (UpdateLine, ReplaceLines) is a sibling of `parity.py` importing
  `harness` and `shapes`: supply its own "old way" / "new way" pair and its own accepted map.
  `SetDimensions` additionally needs a comparator for the `dimensionSetLines` sub-collection —
  the flat 174-field diff does not cover it.
- **When the swaps roll out** the legacy OData path stops being production, and A/B against it
  stops meaning much. At that point record the fields per shape once and assert against the
  snapshot instead, keeping the suite alive as a plain regression test.

## What this is not

Not CI, and not a unit test. It needs a live tenant and real credentials. AL test apps are no
help either — they need BC Docker symbols that only exist on Windows CI runners. This is a
hand-run pre-deploy gate: build → install on both environments → run the suite.
