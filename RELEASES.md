# Releases

## v22.3.0.17 — 2026-08-10
- File: Rutter_AccountLink_22.3.0.17.app (signed, Azure Trusted Signing)
- Submitted to Partner Center for automated validation (~3+ business days)
- Changes: FND-2811 fix — stamp CLE's RTR Sales Invoice Id from "Sales Invoice Entity Aggregate".Id (the field the public salesInvoices API actually binds "id" to) instead of re-deriving it via Draft Invoice SystemId, fixing order-posted invoices getting the wrong GUID; PreviewMode early exit added.
