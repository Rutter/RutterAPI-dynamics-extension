#!/usr/bin/env python3
"""UpdateLines parity suite (FND-4211).

Every case starts from two identical lines created with createLines. One is updated the way
updateJournalLines.ts does it today (PATCH workflowGenJournalLines: the type first, then the
account numbers with the currency fields resent), the other through the updateLines AL
action. Both are read back off page 6407 and every field compared.

Mandatory after any change to the RTR Journal Line Mgt codeunit, alongside parity.py: both
companies, whole suite. See ../../.claude/skills/journal-line-parity/SKILL.md.

Usage: update_parity.py [usa|uae|both]
"""
import json, sys

from harness import CONFIG, Client, check_version, diff, line_no, pmap, print
from update_shapes import KNOWN_GAPS, cases, failures, rules, starts


def create(client, payload, created, n=1):
    """n copies of payload in one createLines call; one id, or a list when n > 1."""
    lines = [dict(payload, lineNumber=line_no()) for _ in range(n)]
    ids = json.loads(client.action("createLines", {"linesJson": json.dumps(lines)})["value"])
    created.extend(ids)
    return ids if n > 1 else ids[0]


def patch(client, line_id, body):
    client.call("PATCH", f"{client.odata}/workflowGenJournalLines({line_id})", body)


def legacy_update(client, line_id, p):
    """updateTopLevelJournalLine: with a type change, everything but the numbers goes first,
    then the numbers with the currency fields resent."""
    numbers = {k: p[k] for k in ("accountNumber", "balAccountNumber") if k in p}
    currency = {k: p[k] for k in ("currencyCode", "RTRCurrencyFactorAPI") if k in p}
    if "accountType" in p or "balAccountType" in p:
        patch(client, line_id, {k: v for k, v in p.items() if k not in numbers})
        if numbers:
            patch(client, line_id, {**currency, **numbers})
    else:
        patch(client, line_id, p)


def update_lines(client, lines):
    return client.action("updateLines", {"linesJson": json.dumps(lines)})["value"]


def attempt(fn, *args):
    try:
        fn(*args)
        return None
    except RuntimeError as e:
        return str(e)


def short(err):
    i = err.find('"message"')
    return err[i + 11:i + 150] if i > 0 else err[:140]


def compare(client, name, legacy_err, al_err, legacy_id, al_id):
    if legacy_err or al_err:
        if name in KNOWN_GAPS and al_err and not legacy_err:
            print(f"  PASS  {name}  (known gap: BC accepts, updateLines refuses)")
            return True
        same = bool(legacy_err) == bool(al_err)
        print(f"  {'PASS' if same else 'DIFF'}  {name}: both rejected" if same else
              f"  DIFF  {name}\n        legacy: {legacy_err and short(legacy_err)}\n        al:     {al_err and short(al_err)}")
        return same
    return diff(name, client.read(legacy_id), client.read(al_id), {})


def run_cases(client, cfg, created):
    s = starts(cfg)

    def case(c):
        name, start, update = c
        try:
            legacy_id, al_id = create(client, s[start], created, 2)
        except RuntimeError as e:
            print(f"  ERROR {name}: could not create the starting lines: {short(str(e))}")
            return False
        return compare(client, name, attempt(legacy_update, client, legacy_id, update),
                       attempt(update_lines, client, [{"id": al_id, **update}]), legacy_id, al_id)
    return all(pmap(case, cases(cfg)))


def run_rules(client, cfg, other, created):
    start = starts(cfg)["G/L credit"]

    def rule(r):
        name, body = r
        legacy_id, al_id = create(client, start, created, 2)
        return compare(client, name, attempt(patch, client, legacy_id, body),
                       attempt(update_lines, client, [{"id": al_id, **body}]), legacy_id, al_id)
    ok = all(pmap(rule, rules(other)))

    legacy_id, al_id = create(client, start, created, 2)
    new_a, new_b = line_no(), line_no()
    patch(client, legacy_id, {"lineNumber": new_a})
    update_lines(client, [{"id": al_id, "lineNumber": new_b}])
    la, lb = client.read(legacy_id), client.read(al_id)
    renamed = la["lineNumber"] == new_a and lb["lineNumber"] == new_b
    if not renamed:
        print(f"  FAIL  lineNumber rename: legacy={la['lineNumber']} al={lb['lineNumber']}")
    return ok & renamed & diff("lineNumber rename", la, lb, {})


def run_multi(client, cfg, created):
    s = starts(cfg)
    updates = [("bank credit", {"accountType": "G/L Account", "accountNumber": cfg["gl"][1]}),
               ("G/L credit", {"description": "second line", "amount": -33.0}),
               ("refund", {"balAccountType": "G/L Account", "balAccountNumber": cfg["gl"][1]})]
    pairs = [(*create(client, s[start], created, 2), u) for start, u in updates]
    for legacy_id, _, u in pairs:
        legacy_update(client, legacy_id, u)
    count = update_lines(client, [{"id": al_id, **u} for _, al_id, u in pairs])
    ok = count == len(pairs)
    print(f"  {'PASS' if ok else 'FAIL'}  {len(pairs)} lines in one call (returned {count})")
    for i, (legacy_id, al_id, _) in enumerate(pairs, 1):
        ok &= diff(f"line {i} of the multi-line call", client.read(legacy_id), client.read(al_id), {})
    return ok


def run_failures(client, cfg, other, created):
    ok, start = True, starts(cfg)["G/L credit"]
    for name, lines in failures(cfg):
        target, second = create(client, start, created, 2)
        taken = client.read(second)["lineNumber"]
        sub = {None: target, "second": second}
        body = [{k: (sub.get(v, v) if k == "id" else taken if v == "taken" else v) for k, v in l.items()}
                for l in lines]
        before = {i: client.read(i) for i in (target, second)}
        err = attempt(update_lines, client, body)
        after = {i: client.read(i) for i in before}
        changed = [k for i in before for k, v in before[i].items()
                   if k != "@odata.etag" and after[i].get(k) != v]
        good = bool(err) and not changed
        print(f"  {'PASS' if good else 'FAIL'}  {name}: "
              f"{'rejected, nothing changed' if good else f'err={err} changed={changed}'}")
        if err:
            print(f"        {short(err)}")
        ok &= good

    if other:
        line_id = create(client, start, created)
        patch(client, line_id, {"journalBatchName": other["code"]})
        err = attempt(update_lines, client, [{"id": line_id, "description": "SHOULD NOT STICK"}])
        print(f"  {'PASS' if err else 'FAIL'}  line from another batch: {short(err) if err else 'accepted'}")
        ok &= bool(err)
    return ok


SWEEP_SKIP = {"id", "@odata.etag", "@odata.context"}


def run_sweep(client, cfg, created):
    """Every field on page 6407, sent back with the value the line already has: BC's PATCH
    leaves the line alone, so updateLines must too. One pair of lines per field."""
    s = starts(cfg)
    start = s.get("credit on an account with VAT defaults", s["G/L credit"])
    start = dict(start, balAccountType="G/L Account", balAccountNumber=cfg["gl"][1])
    fields = sorted(k for k in client.read(create(client, start, created)) if k not in SWEEP_SKIP)
    ids = [i for c in range(0, 2 * len(fields), 50) for i in create(client, start, created, min(50, 2 * len(fields) - c))]
    pairs = list(zip(fields, ids[::2], ids[1::2]))
    # Each line has its own id-derived fields; send what that line holds.
    before = client.read_many(ids)
    legacy_err = dict(zip(fields, pmap(lambda p: attempt(patch, client, p[1], {p[0]: before[p[1]][p[0]]}), pairs)))
    # One call for every field but the known gaps, which updateLines refuses; if that call is
    # refused too, one call per field to find which.
    bodies = {f: {"id": b, f: before[b][f]} for f, _, b in pairs}
    gaps = [f for f in fields if f"same {f}" in KNOWN_GAPS]
    rest = [f for f in fields if f not in gaps]
    singly = gaps + rest if attempt(update_lines, client, [bodies[f] for f in rest]) else gaps
    al_err = dict(zip(singly, pmap(lambda f: attempt(update_lines, client, [bodies[f]]), singly)))
    after = client.read_many(ids)
    ok = True
    for f, a, b in pairs:
        if legacy_err[f] or al_err.get(f):
            ok &= compare(client, f"same {f}", legacy_err[f], al_err.get(f), a, b)
        else:
            ok &= diff(f"same {f}", after[a], after[b], {})
    return ok


def run(key):
    cfg = CONFIG[key]
    print(f"\n{'=' * 70}\n{cfg['label']}  —  batch GENERAL/{cfg['batch_name']}\n{'=' * 70}")
    created, passed, client = [], True, None
    try:
        client = Client(cfg)
        check_version(client)
        other = next((b for b in client.call("GET", f"{client.std}/journals")["value"]
                      if b["code"] != cfg["batch_name"]), None)
        print(f"  second batch for move cases: {other['code'] if other else 'none, move cases skipped'}")

        print("\nupdates (expense update mapper payloads):")
        passed &= run_cases(client, cfg, created)
        print("\nBC PATCH rules:")
        passed &= run_rules(client, cfg, other, created)
        print("\nseveral lines in one call:")
        passed &= run_multi(client, cfg, created)
        print("\nfailure cases:")
        passed &= run_failures(client, cfg, other, created)
        print("\nsame-value sweep (every page 6407 field):")
        passed &= run_sweep(client, cfg, created)
    except (RuntimeError, SystemExit) as e:
        print(f"\nABORTED: {e}")
        passed = False
    finally:
        if created and client:
            print(f"\ncleanup: deleting {len(created)} lines")
            try:
                # One deleteLines call for the lines still in the batch, then the moved ones.
                batch = client.line_ids()
                here = [i for i in created if i in batch]
                if here:
                    client.delete(here)
                left = client.delete_each([i for i in created if i not in here])
            except (RuntimeError, SystemExit) as e:
                left = created
                print(f"  {e}")
            if left:
                print(f"  CLEANUP FAILED for {len(left)} lines (documentNumber is the first 8 characters "
                      f"of their comment) — delete them before the next run")
                passed = False
    return passed


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "both"
    if which not in ("both", *CONFIG):
        sys.exit(f"usage: update_parity.py [{'|'.join(CONFIG)}|both]")
    keys = list(CONFIG) if which == "both" else [which]
    results = {k: run(k) for k in keys}
    print("\n" + "=" * 70)
    for k, v in results.items():
        print(f"{CONFIG[k]['label']}: {'PASS' if v else 'FAIL'}")
    sys.exit(0 if all(results.values()) else 1)
