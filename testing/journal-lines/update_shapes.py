#!/usr/bin/env python3
"""The UpdateLines catalogue — data, no HTTP.

Dynamics has had no PATCH /expenses or /journal_entries traffic to harvest: zero in
production_logged_requests (ops DB, ~16 days retained) and zero updateJournalLines logs in
Datadog over 90 days, checked 2026-10-28. So the updates below are the payloads the expense
update mapper (rutter-backend transformation/expenses/update/expenses_mapper.ts) can send for
the top-level line, and the starting lines follow the real expense creates in that table:
one credit line on a bank or G/L account, memo as description, foreign currency for one
customer, refunds rare.

A case is (name, start, update): `start` is created with createLines, `update` is applied to
it through the legacy PATCHes and through updateLines, and the two lines are compared.
"""
import datetime, uuid

from harness import line_no


def credit_line(cfg, **over):
    """The top-level line of an expense, as the create mapper builds it."""
    doc = uuid.uuid4()
    p = {
        "lineNumber": line_no(),
        "postingDate": datetime.date.today().isoformat(),
        "documentNumber": str(doc)[:8],
        "externalDocumentNumber": str(doc).replace("-", "")[:35],
        "comment": str(doc),
        "description": "Expense | Reference ID: parity | Memo: harness",
        "accountType": "Bank Account",
        "accountNumber": cfg["bank"],
        "amount": -100.0,
    }
    p.update(over)
    return p


def starts(cfg):
    s = {
        "bank credit": credit_line(cfg),
        "G/L credit": credit_line(cfg, accountType="G/L Account", accountNumber=cfg["gl"][0]),
        "foreign-currency credit": credit_line(cfg, accountType="G/L Account", accountNumber=cfg["gl"][0],
                                               currencyCode=cfg["currency"], RTRCurrencyFactorAPI=1.1),
        "refund": credit_line(cfg, accountType="G/L Account", accountNumber=cfg["gl"][0], amount=100.0,
                              balAccountType="Bank Account", balAccountNumber=cfg["bank"]),
        "refund to a G/L account": credit_line(cfg, accountType="G/L Account", accountNumber=cfg["gl"][0], amount=100.0,
                                               balAccountType="G/L Account", balAccountNumber=cfg["gl"][0]),
    }
    if cfg.get("vat_default_account"):
        s["credit on an account with VAT defaults"] = credit_line(
            cfg, accountType="G/L Account", accountNumber=cfg["vat_default_account"])
    return s


def cases(cfg):
    to_gl = {"accountType": "G/L Account", "accountNumber": cfg["gl"][1]}
    to_bank = {"accountType": "Bank Account", "accountNumber": cfg["bank"]}
    memo = {"description": "Expense | Reference ID: parity | Memo: edited"}
    amount = {"amount": -42.5}
    # The mapper resends the currency fields with every account change: validating the
    # account clears them.
    resend = {"currencyCode": cfg["currency"], "RTRCurrencyFactorAPI": 1.1}
    c = [
        ("bank credit: switch to G/L", "bank credit", to_gl),
        ("bank credit: memo only", "bank credit", memo),
        ("bank credit: amount only", "bank credit", amount),
        ("bank credit: account, memo and amount", "bank credit", {**to_gl, **memo, **amount}),
        ("G/L credit: switch to bank", "G/L credit", to_bank),
        ("G/L credit: other G/L account", "G/L credit", {"accountNumber": cfg["gl"][1]}),
        ("G/L credit: account, memo and amount", "G/L credit", {**to_bank, **memo, **amount}),
        ("foreign currency: switch to bank, currency resent", "foreign-currency credit", {**to_bank, **resend}),
        ("foreign currency: memo and amount", "foreign-currency credit", {**memo, **amount}),
        ("refund: balancing account to G/L", "refund",
         {"balAccountType": "G/L Account", "balAccountNumber": cfg["gl"][1]}),
        ("refund: balancing account and memo", "refund",
         {"balAccountType": "G/L Account", "balAccountNumber": cfg["gl"][1], **memo}),
        # The mapper sends the account type with every account change, usually unchanged.
        # Validating an unchanged type clears the account; PATCH skips it (fixed in 22.5.0.45).
        ("same account type, other account", "G/L credit", to_gl),
        ("same account type only", "G/L credit", {"accountType": "G/L Account"}),
        ("same balancing type, other account", "refund to a G/L account",
         {"balAccountType": "G/L Account", "balAccountNumber": cfg["gl"][1]}),
        ("same balancing type only", "refund", {"balAccountType": "Bank Account"}),
        ("custom field", "G/L credit", {"rtrTestFlag": True}),
        ("custom field with a type change", "G/L credit", {"rtrTestFlag": True, **to_bank}),
    ]
    if cfg.get("vat_default_account"):
        c += [
            ("VAT defaults: other G/L account", "credit on an account with VAT defaults", to_gl),
            ("VAT defaults: memo only", "credit on an account with VAT defaults", memo),
        ]
    if cfg.get("vat"):
        c.append(("VAT posting groups", "G/L credit",
                  {"genPostingType": "Purchase", "vatBusPostingGroup": cfg["vat"][0],
                   "vatProdPostingGroup": cfg["vat"][1]}))
    return c


def rules(other_batch):
    """BC's own PATCH behaviour, applied as single PATCHes: both sides must end the same,
    or both must refuse."""
    r = [
        ("read-only systemCreatedEntry", {"systemCreatedEntry": True}),
        ("read-only balanceLcy", {"balanceLcy": 999}),
        ("read-only dimensionSetId", {"dimensionSetId": 999999}),
        ("system field lastModifiedDatetime", {"lastModifiedDatetime": "2020-01-01T00:00:00Z"}),
        ("journalBatchId", {"journalBatchId": other_batch["id"] if other_batch else str(uuid.uuid4())}),
        ("page-only control rtrTestVar", {"rtrTestVar": "x"}),
    ]
    if other_batch:
        r.append(("move to another batch", {"journalBatchName": other_batch["code"]}))
    return r


# BC accepts these and updateLines refuses them. Page-only controls have no table field
# behind them; their value only lands through a page trigger, which AL cannot run.
KNOWN_GAPS = {"page-only control rtrTestVar", "same rtrTestVar"}


def failures(cfg):
    """Each must be rejected and leave every line exactly as it was. `None` stands for the
    line under test; "taken" for the line number of a second line."""
    return [
        ("bank switch with a bad VAT group",
         [{"id": None, "accountType": "Bank Account", "accountNumber": cfg["bank"],
           "description": "SHOULD NOT STICK", "vatProdPostingGroup": "NOPE"}]),
        ("memo and amount with a bad account",
         [{"id": None, "description": "SHOULD NOT STICK", "amount": 77, "accountNumber": "NOPE"}]),
        ("rename onto a line number already taken",
         [{"id": None, "description": "SHOULD NOT STICK", "lineNumber": "taken"}]),
        ("custom field with a bad account",
         [{"id": None, "rtrTestFlag": True, "accountNumber": "NOPE"}]),
        ("good first line, bad second line",
         [{"id": None, "description": "SHOULD NOT STICK", "amount": 55},
          {"id": "second", "accountNumber": "NOPE"}]),
        ("missing id", [{"description": "SHOULD NOT STICK"}]),
        ("unknown id", [{"id": str(uuid.uuid4()), "description": "SHOULD NOT STICK"}]),
        ("empty array", []),
    ]
