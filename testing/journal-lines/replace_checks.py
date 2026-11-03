#!/usr/bin/env python3
"""ReplaceLines checks (FND-3329).

replaceLines only composes deleteLines, updateLines and createLines, whose field behaviour the
two parity suites cover. So this checks the composition: each part matches its own block, and
a failure in any part leaves the batch exactly as it was.

Usage: replace_checks.py [usa|uae|both]
"""
import json, sys, uuid

from harness import CONFIG, Client, check_version, diff, line_no, print
from update_parity import create, update_lines
from update_shapes import starts


def replace(client, delete=(), update=(), new=()):
    body = {"deleteLineIdsJson": json.dumps(list(delete)), "updateLinesJson": json.dumps(list(update)),
            "createLinesJson": json.dumps([dict(p, lineNumber=p.get("lineNumber") or line_no()) for p in new])}
    return json.loads(client.action("replaceLines", body)["value"])


def gone(client, line_id):
    try:
        client.read(line_id)
        return False
    except RuntimeError as e:
        return " 404" in str(e)


def check(name, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {name}{': ' + detail if detail and not ok else ''}")
    return ok


def run_checks(client, cfg, created):
    s = starts(cfg)
    base = s["G/L credit"]
    # No description: CreateLines and UpdateLines treat that differently, so a created line
    # that matches createLines proves replaceLines switched PATCH rules off for the create part.
    new = {k: v for k, v in s["bank credit"].items() if k not in ("description", "lineNumber")}
    upd = {"accountType": "Bank Account", "accountNumber": cfg["bank"], "amount": -42.5}
    ok = True

    old = create(client, base, created, 2)
    ids = replace(client, delete=old, new=[new])
    created.extend(ids)
    ref = create(client, new, created)
    ok &= check("delete and create", all(gone(client, i) for i in old) and len(ids) == 1)
    ok &= diff("  created line matches createLines", client.read(ref), client.read(ids[0]), {})

    dead, target, ref_target = create(client, base, created, 3)
    ids = replace(client, delete=[dead], update=[{"id": target, **upd}], new=[new])
    created.extend(ids)
    update_lines(client, [{"id": ref_target, **upd}])
    ref = create(client, new, created)
    ok &= check("delete, update and create", gone(client, dead) and len(ids) == 1)
    ok &= diff("  updated line matches updateLines", client.read(ref_target), client.read(target), {})
    ok &= diff("  created line after an update matches createLines", client.read(ref), client.read(ids[0]), {})

    dead = create(client, base, created)
    number = client.read(dead)["lineNumber"]
    ids = replace(client, delete=[dead], new=[dict(new, lineNumber=number)])
    created.extend(ids)
    ok &= check("created line reuses the deleted line's number", client.read(ids[0])["lineNumber"] == number)

    dead, target = create(client, base, created, 2)
    number = client.read(dead)["lineNumber"]
    replace(client, delete=[dead], update=[{"id": target, "lineNumber": number}])
    ok &= check("renamed line reuses the deleted line's number", client.read(target)["lineNumber"] == number)

    bad = dict(new, accountType="G/L Account", accountNumber="NOPE")
    for name, part in [("create part fails", {"new": [new, bad]}),
                       ("update part fails", {"update_bad": True}),
                       ("delete part fails", {"delete_extra": str(uuid.uuid4())})]:
        dead, target = create(client, base, created, 2)
        update = [{"id": target, **upd}] + ([{"id": target, "accountNumber": "NOPE"}] if "update_bad" in part else [])
        delete = [dead] + ([part["delete_extra"]] if "delete_extra" in part else [])
        before_ids = client.line_ids()
        before = {i: client.read(i) for i in (dead, target)}
        try:
            created.extend(replace(client, delete=delete, update=update, new=part.get("new", [new])))
            err = None
        except RuntimeError as e:
            err = str(e)
        after = {i: client.read(i) for i in before}
        changed = [k for i in before for k, v in before[i].items() if k != "@odata.etag" and after[i].get(k) != v]
        same_ids = client.line_ids() == before_ids
        ok &= check(f"{name}: everything rolled back", bool(err) and not changed and same_ids,
                    f"err={err and err[:150]} changed={changed} same_ids={same_ids}")

    for empty in ("[]", ""):
        try:
            client.action("replaceLines", dict.fromkeys(("deleteLineIdsJson", "updateLinesJson", "createLinesJson"), empty))
            ok &= check(f"all parts {empty!r}: rejected", False, "accepted")
        except RuntimeError:
            ok &= check(f"all parts {empty!r}: rejected", True)
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
        sys.exit(f"usage: replace_checks.py [{'|'.join(CONFIG)}|both]")
    keys = list(CONFIG) if which == "both" else [which]
    results = {k: run(k) for k in keys}
    print("\n" + "=" * 70)
    for k, v in results.items():
        print(f"{CONFIG[k]['label']}: {'PASS' if v else 'FAIL'}")
    sys.exit(0 if all(results.values()) else 1)
