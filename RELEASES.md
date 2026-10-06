# Releases

## v22.4.0.3 — 2026-10-06
- File: Rutter_AccountLink_22.4.0.3.app (signed, Azure Trusted Signing)
- Submitted to Partner Center for automated validation (~3+ business days)
- Changes: createLines action to create a set of journal lines in one transaction (fixed field order, VAT/tax overrides, balancing posting groups, custom fields via page 6407 incl. page extensions, over-length and date-formula handling).

## v22.4.0.2 — 2026-09-01
- File: Rutter_AccountLink_22.4.0.2.app (signed, Azure Trusted Signing)
- Submitted to Partner Center for automated validation (~3+ business days)
- Changes: invoice credit memos report now shows correct amount applied per invoice; repo file cleanup; new predeploy file-prep skill.

## v22.4.0.1 — 2026-08-26
- File: Rutter_AccountLink_22.4.0.1.app (signed, Azure Trusted Signing)
- Submitted to Partner Center for automated validation (~3+ business days)
- Changes: batch delete journal lines batch operation; VAT country tax area/tax group equivalent support for journal lines; new post-lines action to post a given set of journal lines.

## v22.3.0.17 — 2026-08-10
- File: Rutter_AccountLink_22.3.0.17.app (signed, Azure Trusted Signing)
- Submitted to Partner Center for automated validation (~3+ business days)
- Changes: FND-2811 fix — stamp CLE's RTR Sales Invoice Id from "Sales Invoice Entity Aggregate".Id (the field the public salesInvoices API actually binds "id" to) instead of re-deriving it via Draft Invoice SystemId, fixing order-posted invoices getting the wrong GUID; PreviewMode early exit added.
