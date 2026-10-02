#!/usr/bin/env python3
"""CreateLines parity suite (FND-3323).

Every shape is created twice in the same journal batch: once the way createJournalLines.ts
does it today (POST workflowGenJournalLines with the override fields stripped, then the bank
/ VAT-posting-group / tax-amount PATCHes), once through the createLines AL action. Both lines
are read back off page 6407 and all 174 fields compared.

Mandatory after any change to the RTR Journal Line Mgt codeunit: both companies, whole suite.
See ../../.claude/skills/journal-line-parity/SKILL.md.

Usage: parity.py [usa|uae|both]
"""
import json, sys

from harness import CONFIG, Client, check_version, diff, line_no, print, resolve
from shapes import ACCEPTED, bank_deposit_lines, failure_payloads, shapes

# Live on the extension's overrides page, not page 6407 — the backend strips them from the
# POST and applies them in the later PATCHes.
OVERRIDE_FIELDS = ("RTRVATAmountAPI", "RTRVatBusPostingGroupAPI", "RTRVatProdPostingGroupAPI")


def legacy_create(client, p, created):
    """What createJournalLines.ts does today: POST, then the follow-up PATCHes.

    `created` is appended to as soon as the line exists — a PATCH below can fail, and the
    line still has to be cleaned up.
    """
    body = {k: v for k, v in p.items()
            if not k.startswith("_") and k not in OVERRIDE_FIELDS}
    line = client.call("POST", f"{client.odata}/workflowGenJournalLines", body)
    created.append(line["id"])

    # Both sides, as updateJournalLinesWithBankAccountNumber does. Description is re-sent
    # because validating a bank account overwrites it.
    patch = {}
    if p.get("_bankAccountNumber"):
        patch["accountNumber"] = p["_bankAccountNumber"]
    if p.get("_balBankAccountNumber"):
        patch["balAccountNumber"] = p["_balBankAccountNumber"]
    if patch:
        patch["description"] = line["description"]
        line = client.call("PATCH", f"{client.odata}/workflowGenJournalLines({line['id']})", patch)

    groups = {k: p[k] for k in OVERRIDE_FIELDS[1:] if k in p}
    if groups:
        client.call("PATCH", f"{client.rutter}/genJournalLineOverrides({line['id']})", groups)
    if "RTRVATAmountAPI" in p:
        client.call("PATCH", f"{client.rutter}/genJournalLineOverrides({line['id']})",
                    {"RTRVATAmountAPI": p["RTRVATAmountAPI"]})
    return line["id"]


def al_create(client, payloads):
    """One createLines call, sending the account exactly as the shape declares it.

    Whether the account arrives as an id or a number is not cosmetic: the AL block restores
    the account's defaults only for ids, mirroring the old path, where only a validated
    number picked them up. A shape that sent an id one way and a number the other would be
    comparing two different behaviours. The one exception is a bank line, which the backend
    creates by id and then patches to the bank number — the AL block does it in one go.
    """
    body = []
    for p in payloads:
        b = {k: v for k, v in p.items() if not k.startswith("_")}
        b["lineNumber"] = line_no()      # same batch: cannot reuse the legacy line's
        if p.get("_bankAccountNumber"):
            b.pop("accountId", None)
            b["accountNumber"] = p["_bankAccountNumber"]
        if p.get("_balBankAccountNumber"):
            b["balAccountNumber"] = p["_balBankAccountNumber"]
        body.append(b)
    return json.loads(client.action("createLines", {"linesJson": json.dumps(body)})["value"])


def bank_deposit_batch(client, cfg):
    lines = bank_deposit_lines(cfg)
    try:
        ids = al_create(client, lines)
    except RuntimeError as e:
        print(f"  FAIL  {len(lines)}-line bank deposit in one call: {e}")
        return [], False
    ok = len(ids) == len(lines)
    print(f"  {'PASS' if ok else 'FAIL'}  {len(lines)}-line bank deposit in one call "
          f"({len(ids)} ids returned)")
    # The only many-line call, so check each line landed with what was sent, in order.
    for i, (sent, line_id) in enumerate(zip(lines, ids), 1):
        got = client.read(line_id)
        wrong = [(k, sent[k], got.get(k)) for k in ("accountNumber", "amount", "description")
                 if got.get(k) != sent[k]]
        if wrong:
            ok = False
            print(f"  FAIL  line {i}: " + ", ".join(f"{k} sent={s!r} got={g!r}" for k, s, g in wrong))
    return ids, ok


def failure_cases(client, cfg, fx, created):
    ok = True
    for name, payload in failure_payloads(cfg, fx):
        before = client.line_ids()
        try:
            created += al_create(client, payload)   # unexpected, but still ours to delete
            print(f"  FAIL  {name}: call succeeded, expected an error")
            ok = False
        except RuntimeError as e:
            left = client.line_ids() - before
            if left:
                created += left                      # cleanup still has to remove them
                print(f"  FAIL  {name}: rejected but left {len(left)} line(s) behind")
                ok = False
            else:
                msg = str(e)
                i = msg.find("message")
                print(f"  PASS  {name}: rejected, nothing inserted")
                print(f"        {msg[i:i + 150] if i > 0 else msg[:150]}")
    return ok


def run(key):
    cfg = CONFIG[key]
    print(f"\n{'=' * 70}\n{cfg['label']}  —  batch GENERAL/{cfg['batch_name']}\n{'=' * 70}")
    created, passed = [], True
    client = None

    # Whatever happens — a dropped connection, an expired token — the lines created so far
    # must still be deleted, or the next run's failure-case counts compare against a dirty
    # batch. An error here must also not take the other company down with it.
    try:
        # Setup calls sys.exit on a missing fixture or a stale build. Catching SystemExit
        # turns that into a failed result for this company rather than skipping the next one.
        client = Client(cfg)
        check_version(client)
        fx = resolve(client)

        print("\nparity shapes:")
        for name, payload in shapes(cfg, fx):
            try:
                legacy_id = legacy_create(client, dict(payload), created)
                al_id = al_create(client, [dict(payload)])[0]
                created.append(al_id)
                al_line = client.read(al_id)
                passed &= diff(name, client.read(legacy_id), al_line, ACCEPTED)
                # Values the AL line must hold whatever legacy does.
                for k, want in payload.get("_expect", {}).items():
                    if al_line.get(k) != want:
                        print(f"  FAIL  {name}: AL {k}={al_line.get(k)!r}, expected {want!r}")
                        passed = False
            except RuntimeError as e:
                print(f"  ERROR {name}: {e}")
                passed = False

        print("\nbatch stress:")
        ids, ok = bank_deposit_batch(client, cfg)
        created += ids
        passed &= ok

        print("\nfailure cases:")
        passed &= failure_cases(client, cfg, fx, created)
    except (RuntimeError, SystemExit) as e:
        print(f"\nABORTED: {e}")
        passed = False
    finally:
        if created and client:
            print(f"\ncleanup: deleting {len(created)} lines")
            try:
                client.delete(created)
            except RuntimeError as e:
                print(f"  CLEANUP FAILED, {len(created)} lines left in {cfg['batch_name']}: {e}")
                print("  delete them before the next run — see the skill's Traps section")
                passed = False
    return passed


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "both"
    if which not in ("both", *CONFIG):
        sys.exit(f"usage: parity.py [{'|'.join(CONFIG)}|both]")
    keys = list(CONFIG) if which == "both" else [which]
    results = {k: run(k) for k in keys}
    print("\n" + "=" * 70)
    for k, v in results.items():
        print(f"{CONFIG[k]['label']}: {'PASS' if v else 'FAIL'}")
    sys.exit(0 if all(results.values()) else 1)
