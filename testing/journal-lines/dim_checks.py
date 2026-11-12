#!/usr/bin/env python3
"""Dimension checks (FND-3324).

The parity suites compare the 174 flat fields of page 6407, which leaves out the
dimensionSetLines sub-collection. This checks dimensions directly, on every block that takes
them (createLines, updateLines, replaceLines, setDimensions), and posts one pair to confirm the
dimensions reach the G/L entries.

Merge rule under test: dimensions the line already carries (account or balancing-account
defaults) are kept; a sent code replaces the value for that code.

Usage: dim_checks.py [usa|uae|both]
"""
import json, sys, uuid

from harness import CONFIG, Client, check_version, line_no, print, resolve
from update_shapes import credit_line

DEPT, AREA, GROUP = "DEPARTMENT", "AREA", "CUSTOMERGROUP"


def dl(*pairs):
    return [{"code": c, "valueCode": v} for c, v in pairs]


def dims(client, line_id):
    rows = client.call("GET", f"{client.std}/journals({client.cfg['batch_id']})/journalLines({line_id})/dimensionSetLines")["value"]
    return sorted((r["code"], r["valueCode"]) for r in rows)


def check(name, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {name}{': ' + str(detail) if detail and not ok else ''}")
    return ok


def attempt(fn):
    try:
        fn()
        return None
    except RuntimeError as e:
        # The body is JSON, so quotes in BC's message arrive escaped.
        return str(e).replace('\\"', '"')


def gl_line(cfg, account, amount=-100.0, dimensions=None, **over):
    p = credit_line(cfg, accountType="G/L Account", accountNumber=account, amount=amount, **over)
    if dimensions is not None:
        p["dimensionSetLines"] = dimensions
    return p


def create(client, created, *payloads):
    lines = [dict(p, lineNumber=line_no()) for p in payloads]
    ids = json.loads(client.action("createLines", {"linesJson": json.dumps(lines)})["value"])
    created.extend(ids)
    return ids


def set_dims(client, *pairs):
    return client.action("setDimensions", {"linesJson": json.dumps([{"id": i, "dimensionSetLines": d} for i, d in pairs])})


def update(client, lines):
    return client.action("updateLines", {"linesJson": json.dumps(lines)})


def replace(client, update=(), new=()):
    body = {"deleteLineIdsJson": "", "updateLinesJson": json.dumps(list(update)),
            "createLinesJson": json.dumps([dict(p, lineNumber=line_no()) for p in new])}
    return json.loads(client.action("replaceLines", body)["value"])


def shortcuts_match(client, line_id, global_codes):
    """Shortcut Dimension 1/2 Code must equal the set's value for the two global dimensions."""
    line, d = client.read(line_id), dict(dims(client, line_id))
    want = [d.get(c, "") for c in global_codes]
    got = [line.get("shortcutDimension1Code", ""), line.get("shortcutDimension2Code", "")]
    return want == got, f"want={want} got={got}"


def global_dimension_codes(client, cfg, created):
    """Which dimensions are the company's global 1 and 2, read off a line carrying all three."""
    probe = (DEPT, "SALES"), (AREA, "30"), (GROUP, "LARGE")
    (lid,) = create(client, created, gl_line(cfg, cfg["gl"][0], dimensions=dl(*probe)))
    line = client.read(lid)
    by_value = {v: c for c, v in probe}
    codes = [by_value.get(line.get("shortcutDimension1Code")), by_value.get(line.get("shortcutDimension2Code"))]
    client.delete([lid])
    created.remove(lid)
    return codes


def run_checks(client, cfg, created):
    ok = True
    gl, gl2 = cfg["gl"]
    fx = resolve(client)
    gcodes = global_dimension_codes(client, cfg, created)
    print(f"  global dimensions: {gcodes}")
    # Global dimension 1/2 for the shortcut checks; fall back to plain codes if a company maps neither.
    g1 = gcodes[0] or DEPT
    g1_values = {DEPT: ("SALES", "PROD"), AREA: ("30", "40"), GROUP: ("LARGE", "SMALL")}[g1]

    # Create, and the shortcut fields that go with it.
    a, b = create(client, created, gl_line(cfg, gl, dimensions=dl((g1, g1_values[0]), (AREA if g1 != AREA else DEPT, "40" if g1 != AREA else "SALES"))),
                  gl_line(cfg, gl2, 100.0, dimensions=dl((g1, g1_values[1]))))
    ok &= check("createLines: dimensions on each line",
                dims(client, a) == sorted(dl_pairs := [(g1, g1_values[0]), (AREA, "40") if g1 != AREA else (DEPT, "SALES")]) and dims(client, b) == [(g1, g1_values[1])],
                [dims(client, a), dims(client, b)])
    match, detail = shortcuts_match(client, a, gcodes)
    ok &= check("createLines: shortcut dimension codes follow the set", match, detail)

    # setDimensions: override one code, keep the rest; shortcut follows; retry is a no-op.
    set_dims(client, (a, dl((g1, g1_values[1]))))
    after = dims(client, a)
    ok &= check("setDimensions: sent code replaced, others kept",
                after == sorted([(g1, g1_values[1])] + [p for p in dl_pairs if p[0] != g1]), after)
    match, detail = shortcuts_match(client, a, gcodes)
    ok &= check("setDimensions: shortcut dimension codes follow the set", match, detail)
    set_dims(client, (a, dl((g1, g1_values[1]))))
    ok &= check("setDimensions: retry leaves the set unchanged", dims(client, a) == after, dims(client, a))

    # updateLines: dimensions only, then together with an account change.
    update(client, [{"id": b, "dimensionSetLines": dl((GROUP, "SMALL"))}])
    ok &= check("updateLines: dimensions merged", dims(client, b) == sorted([(g1, g1_values[1]), (GROUP, "SMALL")]), dims(client, b))
    match, detail = shortcuts_match(client, b, gcodes)
    ok &= check("updateLines: shortcut dimension codes follow the set", match, detail)

    new_account = cfg.get("dim_default_account") or gl2
    (c,) = create(client, created, gl_line(cfg, gl, dimensions=dl((GROUP, "LARGE"))))
    update(client, [{"id": c, "accountNumber": new_account, "dimensionSetLines": dl((AREA, "30"))}])
    got = dims(client, c)
    want_default = [(DEPT, "ADM")] if cfg.get("dim_default_account") else []
    # Validating the new account rebuilds the set from its defaults (BC's own PATCH does the
    # same), so the old GROUP goes; the sent AREA must land on top of the new defaults.
    ok &= check("updateLines: account change + dimensions = new account defaults + sent",
                got == sorted(want_default + [(AREA, "30")]), got)
    print(f"        (previous dimensions after the account change: {'kept' if (GROUP, 'LARGE') in got else 'dropped'})")

    # Rollback: one bad entry fails the whole call, nothing changes.
    snap_ids, snap_a, snap_b = client.line_ids(), dims(client, a), dims(client, b)
    err = attempt(lambda: create(client, created, gl_line(cfg, gl, dimensions=dl((g1, g1_values[0]))),
                                 gl_line(cfg, gl2, 100.0, dimensions=dl((DEPT, "NOPE_XX")))))
    ok &= check("createLines: bad dimension on line 2 leaves no lines", bool(err) and client.line_ids() == snap_ids and "Line 2" in err, err)
    err = attempt(lambda: set_dims(client, (a, dl((g1, g1_values[0]))), (b, dl(("NODIM_XX", "A")))))
    ok &= check("setDimensions: bad dimension on line 2 leaves line 1 unchanged",
                bool(err) and dims(client, a) == snap_a and "Line 2" in err, err)
    err = attempt(lambda: update(client, [{"id": a, "amount": -7, "dimensionSetLines": dl((AREA, "30"))},
                                          {"id": b, "dimensionSetLines": dl((AREA, "NOPE_XX"))}]))
    ok &= check("updateLines: bad dimension on line 2 leaves line 1 unchanged",
                bool(err) and dims(client, a) == snap_a and client.read(a)["amount"] != -7 and "Line 2" in err, err)
    for part, upd, new, want in [
            ("update part", [{"id": a, "amount": -8, "dimensionSetLines": dl((AREA, "NOPE_XX"))}], [gl_line(cfg, gl)], "Update line 1"),
            ("create part", [{"id": a, "amount": -8, "dimensionSetLines": dl((AREA, "30"))}],
             [gl_line(cfg, gl, dimensions=dl((AREA, "NOPE_XX")))], "Create line 1")]:
        before = client.read(a)
        err = attempt(lambda: created.extend(replace(client, update=upd, new=new)))
        ok &= check(f"replaceLines: bad dimension in the {part} rolls back everything",
                    bool(err) and want in err and client.line_ids() == snap_ids and dims(client, a) == snap_a
                    and client.read(a)["amount"] == before["amount"], err)
    ids = replace(client, update=[{"id": a, "dimensionSetLines": dl((GROUP, "MEDIUM"))}],
                  new=[gl_line(cfg, gl, dimensions=dl((GROUP, "SMALL")))])
    created.extend(ids)
    ok &= check("replaceLines: dimensions applied in both parts",
                (GROUP, "MEDIUM") in dims(client, a) and dims(client, ids[0]) == [(GROUP, "SMALL")], [dims(client, a), dims(client, ids[0])])

    # Payload validation.
    for name, entries, want in [
            ("same code twice", dl((AREA, "30"), (AREA, "40")), "more than once"),
            ("missing valueCode", [{"code": AREA}], '"valueCode" is required'),
            ("missing code", [{"valueCode": "30"}], '"code" is required'),
            ("extra key", [{"code": AREA, "valueCode": "30", "displayName": "x"}], '"displayName"'),
            ("unknown dimension", dl(("NODIM_XX", "A")), "does not exist"),
            ("unknown value", dl((AREA, "NOPE_XX")), "has no value"),
            ("not an array", {"code": AREA, "valueCode": "30"}, "must be an array"),
            # BC's own Dimension Set Entry validation; the standard API accepts it and posting fails later.
            ("an End-Total value", dl((AREA, "45")), "must not be End-Total")]:
        err = attempt(lambda: set_dims(client, (a, entries)))
        ok &= check(f"rejects {name}", bool(err) and want in err, err)

    set_dims(client, (a, dl((AREA, "10"))))
    ok &= check("accepts a Begin-Total value (postable)", (AREA, "10") in dims(client, a), dims(client, a))

    # Account defaults (only CRONUS UAE 2 has an account carrying a default dimension).
    if cfg.get("dim_default_account"):
        acct = cfg["dim_default_account"]
        acct_id = fx["gl_id"][acct]
        by_number = create(client, created, gl_line(cfg, acct, dimensions=[]), gl_line(cfg, acct, dimensions=dl((AREA, "30"))),
                           gl_line(cfg, acct, dimensions=dl((DEPT, "SALES"))))
        r = [dims(client, i) for i in by_number]
        ok &= check("account default (by number): kept with no dimensions sent", r[0] == [(DEPT, "ADM")], r[0])
        ok &= check("account default (by number): merged with another code", r[1] == [(AREA, "30"), (DEPT, "ADM")], r[1])
        ok &= check("account default (by number): sent code overrides it", r[2] == [(DEPT, "SALES")], r[2])

        def by_id(**over):
            p = gl_line(cfg, acct, **over)
            p.pop("accountNumber")
            p["accountId"] = acct_id
            return p
        ids = create(client, created, by_id(), by_id(dimensionSetLines=dl((AREA, "30"))))
        r = [dims(client, i) for i in ids]
        # By id the OData path never applied the account's defaults (RestoreAccountDefaults).
        ok &= check("account by id: no default, as on the OData path", r[0] == [], r[0])
        ok &= check("account by id: sent dimensions applied", r[1] == [(AREA, "30")], r[1])

        # Balancing-account defaults: by number (validated) and by id (RebuildDimensionsFromBalAccount).
        def with_bal(by, sent):
            p = gl_line(cfg, gl, balAccountType="G/L Account", balAccountNumber=acct,
                        dimensions=sent)
            if by == "id":
                p.pop("accountNumber")
                p["accountId"] = fx["gl_id"][gl]
            return p
        for by in ("number", "id"):
            ids = create(client, created, with_bal(by, None), with_bal(by, dl((AREA, "30"))), with_bal(by, dl((DEPT, "SALES"))))
            r = [dims(client, i) for i in ids]
            ok &= check(f"bal account default (account by {by}): kept", r[0] == [(DEPT, "ADM")], r[0])
            ok &= check(f"bal account default (account by {by}): merged", r[1] == [(AREA, "30"), (DEPT, "ADM")], r[1])
            ok &= check(f"bal account default (account by {by}): sent code overrides", r[2] == [(DEPT, "SALES")], r[2])

    # Posting: the dimensions reach the G/L entries.
    doc = "DIM" + uuid.uuid4().hex[:7].upper()
    sent = dl((g1, g1_values[0]), (GROUP, "LARGE"))
    pair = create(client, created, gl_line(cfg, gl, -10.0, sent, documentNumber=doc),
                  gl_line(cfg, gl2, 10.0, sent, documentNumber=doc))
    err = attempt(lambda: client.action("postLines", {"lineIdsJson": json.dumps(pair)}))
    if err:
        ok &= check("postLines with dimensions", False, err)
    else:
        for i in pair:
            created.remove(i)
        entries = client.call("GET", f"{client.std}/generalLedgerEntries?$filter=documentNumber eq '{doc}'&$expand=dimensionSetLines".replace(" ", "%20"))["value"]
        got = [sorted((d["code"], d["valueCode"]) for d in e["dimensionSetLines"]) for e in entries]
        want = sorted((d["code"], d["valueCode"]) for d in sent)
        ok &= check(f"posted G/L entries carry the dimensions ({len(entries)} entries, doc {doc})",
                    len(entries) >= 2 and all(g == want for g in got), got)
    return ok


def run(key):
    cfg = CONFIG[key]
    print(f"\n{'=' * 70}\n{cfg['label']}  —  batch GENERAL/{cfg['batch_name']}\n{'=' * 70}")
    created, passed, client = [], True, None
    try:
        client = Client(cfg)
        check_version(client)
        passed = run_checks(client, cfg, created)
    except (RuntimeError, SystemExit) as e:
        print(f"\nABORTED: {e}")
        passed = False
    finally:
        if created and client:
            batch = client.line_ids()
            left = [i for i in created if i in batch]
            print(f"\ncleanup: deleting {len(left)} lines")
            try:
                if left:
                    client.delete(left)
            except (RuntimeError, SystemExit) as e:
                print(f"  CLEANUP FAILED for {len(left)} lines, delete them before the next run: {e}")
                passed = False
    return passed


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "both"
    if which not in ("both", *CONFIG):
        sys.exit(f"usage: dim_checks.py [{'|'.join(CONFIG)}|both]")
    keys = list(CONFIG) if which == "both" else [which]
    results = {k: run(k) for k in keys}
    print("\n" + "=" * 70)
    for k, v in results.items():
        print(f"{CONFIG[k]['label']}: {'PASS' if v else 'FAIL'}")
    sys.exit(0 if all(results.values()) else 1)
