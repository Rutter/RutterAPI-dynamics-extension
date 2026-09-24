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


def legacy_create(client, p):
    """What createJournalLines.ts does today: POST, then the follow-up PATCHes."""
    body = {k: v for k, v in p.items()
            if not k.startswith("_") and k not in OVERRIDE_FIELDS}
    line = client.call("POST", f"{client.odata}/workflowGenJournalLines", body)

    if p.get("_bankAccountNumber"):
        # description is re-sent because validating the bank account mangles it
        line = client.call("PATCH", f"{client.odata}/workflowGenJournalLines({line['id']})",
                           {"accountNumber": p["_bankAccountNumber"],
                            "description": line["description"]})

    groups = {k: p[k] for k in OVERRIDE_FIELDS[1:] if k in p}
    if groups:
        client.call("PATCH", f"{client.rutter}/genJournalLineOverrides({line['id']})", groups)
    if "RTRVATAmountAPI" in p:
        client.call("PATCH", f"{client.rutter}/genJournalLineOverrides({line['id']})",
                    {"RTRVATAmountAPI": p["RTRVATAmountAPI"]})
    return line["id"]


def al_create(client, payloads):
    """One createLines call. Account numbers win over ids, as the swap will send them."""
    body = []
    for p in payloads:
        b = {k: v for k, v in p.items() if not k.startswith("_")}
        b["lineNumber"] = line_no()      # same batch: cannot reuse the legacy line's
        number = p.get("_bankAccountNumber") or p.get("_accountNumber")
        if number:
            b.pop("accountId", None)
            b["accountNumber"] = number
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
    return ids, ok


def failure_cases(client, cfg, fx):
    ok = True
    for name, payload in failure_payloads(cfg, fx):
        before = client.count_lines()
        try:
            al_create(client, payload)
            print(f"  FAIL  {name}: call succeeded, expected an error")
            ok = False
        except RuntimeError as e:
            after = client.count_lines()
            if after != before:
                print(f"  FAIL  {name}: rejected but left {after - before} line(s) behind")
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
    client = Client(cfg)
    check_version(client)
    fx = resolve(client)
    created, passed = [], True

    print("\nparity shapes:")
    for name, payload in shapes(cfg, fx):
        try:
            legacy_id = legacy_create(client, dict(payload))
            created.append(legacy_id)
            al_id = al_create(client, [dict(payload)])[0]
            created.append(al_id)
            passed &= diff(name, client.read(legacy_id), client.read(al_id), ACCEPTED)
        except RuntimeError as e:
            print(f"  ERROR {name}: {e}")
            passed = False

    print("\nbatch stress:")
    ids, ok = bank_deposit_batch(client, cfg)
    created += ids
    passed &= ok

    print("\nfailure cases:")
    passed &= failure_cases(client, cfg, fx)

    if created:
        print(f"\ncleanup: deleting {len(created)} lines")
        try:
            client.delete(created)
        except RuntimeError as e:
            print(f"  CLEANUP FAILED, lines left in {cfg['batch_name']}: {e}")
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
