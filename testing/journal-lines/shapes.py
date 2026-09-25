#!/usr/bin/env python3
"""The payload catalogue — data, no HTTP.

Every shape is modelled on a real production payload. They were harvested from Datadog:

    env:production "Creating dimensionSetLines for journalLines"
    extra_fields: ["journalLinesRequest"]

That log carries the complete body the create strategy sent to Business Central. Re-run the
query before adding shapes — customer traffic is the only honest source for what a block has
to survive. The three that seeded this file:

  - Alaan (UAE):               AED + RTRCurrencyFactorAPI 3.6725 + vatProdPostingGroup
  - floatcard (CRONUS Canada): taxAreaCode "ON" + taxGroupCode FULLTAX
  - Alternative Payments:      21-line bank deposit, sourceType, lowercase "G/L account"

dimensionSetLines are deliberately absent: the backend applies them through a separate
endpoint after creation, so including them here would only diff dimensionSetId. FND-3324
owns moving that into AL.

Shapes take (cfg, fx) — the company config and the fixtures resolved from the API — so the
same catalogue retargets to any sandbox company without edits.
"""
import datetime, uuid

from harness import line_no

# Differences we have accepted, keyed by shape name. Legacy applies Account No. through
# "Account Id" at the very end of page 6407, so its Account No. is still blank when the bal
# account validates — which is why BC overwrites the description there and the AL block does
# not. Matching it would mean reintroducing the mismatched in-between state the block removes.
# balanceLcy is the journal page's running-balance display field and is never posted.
# Add an entry only with the reason written down; an unexplained one is a hidden regression.
ACCEPTED = {"bal account pair": {"description", "balanceLcy"}}


def base_line(cfg, fx, **over):
    doc = uuid.uuid4()
    gl = cfg["gl"][0]
    p = {
        "journalTemplateName": "GENERAL",
        "journalBatchName": cfg["batch_name"],
        "lineNumber": line_no(),
        "postingDate": datetime.date.today().isoformat(),
        "documentNumber": str(doc)[:8],
        "externalDocumentNumber": str(doc).replace("-", "")[:35],
        "comment": str(doc),
        "description": "Expense | Reference ID: parity | Memo: harness",
        "accountType": "G/L Account",
        "accountId": fx["gl_id"][gl],
        "_accountNumber": gl,
        "amount": 700.0,
    }
    p.update(over)
    return {k: v for k, v in p.items() if v is not None}


def shapes(cfg, fx):
    """One line per shape, as (name, payload). Company-specific shapes are skipped where the
    company lacks the setup — USA has tax areas, UAE 2 has VAT posting groups."""
    gl2 = cfg["gl"][1]
    out = [
        ("expense pair: debit", base_line(cfg, fx)),
        ("expense pair: credit", base_line(cfg, fx, amount=-700.0,
                                           accountId=fx["gl_id"][gl2], _accountNumber=gl2)),
        ("lowercase accountType (Alternative Payments)",
         base_line(cfg, fx, accountType="G/L account")),
        ("bank line, two-step PATCH case",
         base_line(cfg, fx, accountType="Bank Account", accountId=fx["bank_gl_id"],
                   _accountNumber=None, _bankAccountNumber=cfg["bank"])),
        ("linked payment line (sourceType)",
         base_line(cfg, fx, amount=-234.47, sourceType="Bank Account",
                   accountType="G/L account",
                   description="INVOICE_PAYMENT:37c59bd0-2eb3-f111-aaa8-000d3a4d7296")),
        ("bal account pair", base_line(cfg, fx, balAccountType="G/L Account", balAccountNumber=gl2)),
        ("custom field passthrough", base_line(cfg, fx, onHold="RTR")),
    ]
    if cfg["currency"]:
        out.append(("foreign currency + factor (Alaan)",
                    base_line(cfg, fx, amount=57.14, currencyCode=cfg["currency"],
                              RTRCurrencyFactorAPI=3.6725)))
    if cfg["vat"]:
        bus, prod = cfg["vat"]
        out += [
            ("VAT prod posting group (Alaan)",
             base_line(cfg, fx, vatProdPostingGroup=prod, genPostingType="Purchase")),
            ("VAT bus + prod override",
             base_line(cfg, fx, genPostingType="Purchase",
                       RTRVatBusPostingGroupAPI=bus, RTRVatProdPostingGroupAPI=prod)),
            ("VAT + tax amount override",
             base_line(cfg, fx, genPostingType="Purchase",
                       RTRVatBusPostingGroupAPI=bus, RTRVatProdPostingGroupAPI=prod,
                       RTRVATAmountAPI=1.5)),
            ("AED + factor + VAT group (full Alaan shape)",
             base_line(cfg, fx, amount=57.14, currencyCode=cfg["currency"],
                       RTRCurrencyFactorAPI=3.6725, vatProdPostingGroup=prod)),
        ]
    # The two restore paths: validating Account No. pulls the account's VAT setup
    # (Validate("VAT Prod. Posting Group") -> VAT %, VAT Amount, VAT Base Amount) and its
    # default dimensions (CreateDimFromDefaultDim). The old accountId path did neither, so
    # RestoreAccountDefaults has to put back whatever the caller did not send.
    if cfg.get("vat_default_account"):
        acct = cfg["vat_default_account"]
        out.append(("account with VAT posting groups, none sent",
                    base_line(cfg, fx, accountId=fx["gl_id"][acct], _accountNumber=acct)))
    if cfg.get("dim_default_account"):
        acct = cfg["dim_default_account"]
        out.append(("account with default dimension, none sent",
                    base_line(cfg, fx, accountId=fx["gl_id"][acct], _accountNumber=acct)))

    if cfg["tax"]:
        area, group = cfg["tax"]
        out.append(("sales tax (floatcard)",
                    base_line(cfg, fx, amount=76.83, taxAreaCode=area, taxGroupCode=group,
                              taxLiable=True, genPostingType="Purchase")))
    return out


def bank_deposit_lines(cfg):
    """Alternative Payments' real shape: a pile of fee lines, the linked payments they settle,
    and one bank line — all in ONE call. The batch-atomicity stress case."""
    doc = uuid.uuid4()
    common = dict(journalTemplateName="GENERAL", journalBatchName=cfg["batch_name"],
                  documentNumber=str(doc)[:8], externalDocumentNumber=str(doc).replace("-", "")[:35],
                  comment=str(doc), postingDate=datetime.date.today().isoformat())
    lines = [{**common, "lineNumber": line_no(), "accountType": "G/L account",
              "accountNumber": cfg["gl"][0], "amount": 0.5, "description": "Payment Fee"}
             for _ in range(11)]
    lines += [{**common, "lineNumber": line_no(), "accountType": "G/L account",
               "accountNumber": cfg["gl"][1], "amount": amt, "sourceType": "Bank Account",
               "description": f"INVOICE_PAYMENT:{uuid.uuid4()}"}
              for amt in (-234.47, -150.0, -86.51, -450.0, -137.25)]
    lines.append({**common, "lineNumber": line_no(), "accountType": "Bank account",
                  "accountNumber": cfg["bank"], "amount": 111.76, "description": "ALT No2123"})
    return lines


def failure_payloads(cfg, fx):
    """Payloads the block must reject outright, leaving nothing behind."""
    return [
        ("bad accountType", [base_line(cfg, fx, accountType="Nonsense Account")]),
        ("unknown custom field", [base_line(cfg, fx, notAFieldAtAll="x")]),
        ("nested field (dimensionSetLines)",
         [base_line(cfg, fx, dimensionSetLines=[{"classId": "x", "template": {"code": "DEPT"}}])]),
        ("mid-batch failure rolls back",
         [base_line(cfg, fx), base_line(cfg, fx),
          base_line(cfg, fx, accountId=None, _accountNumber="NOPE")]),
    ]
