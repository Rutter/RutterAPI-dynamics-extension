#if PTE
codeunit 71693 "RTR Rutter Management"
#else
codeunit 71692575 "RTR Rutter Management"
#endif
{
    trigger OnRun()
    begin

    end;

    [EventSubscriber(ObjectType::Table, Database::"Cust. Ledger Entry", 'OnAfterCopyCustLedgerEntryFromGenJnlLine', '', false, false)]
    local procedure CustLedgerEntryOnAfterCopyCustLedgerEntryFromGenJnlLine(var CustLedgerEntry: Record "Cust. Ledger Entry"; GenJournalLine: Record "Gen. Journal Line")
    begin
        CustLedgerEntry."RTR Journal Id" := GenJournalLine.SystemId;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Vendor Ledger Entry", 'OnAfterCopyVendLedgerEntryFromGenJnlLine', '', false, false)]
    local procedure VendLedgerEntryOnAfterCopyVendLedgerEntryFromGenJnlLine(var VendorLedgerEntry: Record "Vendor Ledger Entry"; GenJournalLine: Record "Gen. Journal Line")
    begin
        VendorLedgerEntry."RTR Journal Id" := GenJournalLine.SystemId;
    end;

    // Stable id surviving renames (Document No. on the CLE is a point-in-time copy BC never updates).
    // Read directly from "Sales Invoice Entity Aggregate" — the literal table the public salesInvoices
    // API binds "id" to — instead of re-deriving via Draft Invoice SystemId: live testing showed that
    // field can be non-null on the posted header even when the API itself returns a different id for
    // order-posted invoices, so re-deriving it ourselves risked drifting from what the API actually returns.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", 'OnAfterPostSalesDoc', '', false, false)]
    local procedure SalesPostOnAfterPostSalesDoc(var SalesHeader: Record "Sales Header"; var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line"; SalesShptHdrNo: Code[20]; RetRcpHdrNo: Code[20]; SalesInvHdrNo: Code[20]; SalesCrMemoHdrNo: Code[20]; CommitIsSuppressed: Boolean; InvtPickPutaway: Boolean; var CustLedgerEntry: Record "Cust. Ledger Entry"; WhseShip: Boolean; WhseReceiv: Boolean; PreviewMode: Boolean)
    var
        SalesInvoiceEntityAggregate: Record "Sales Invoice Entity Aggregate";
        SalesCrMemoEntityBuffer: Record "Sales Cr. Memo Entity Buffer";
    begin
        if CustLedgerEntry."Entry No." = 0 then
            exit;
        if PreviewMode then
            exit;

        // Same reasoning for credit memos: "Sales Cr. Memo Entity Buffer" is what
        // the public salesCreditMemos API binds "id" to.
        if SalesInvoiceEntityAggregate.Get(SalesInvHdrNo, true) then
            CustLedgerEntry."RTR Sales Invoice Id" := SalesInvoiceEntityAggregate.Id
        else
            if SalesCrMemoEntityBuffer.Get(SalesCrMemoHdrNo, true) then
                CustLedgerEntry."RTR Sales Cr. Memo Id" := SalesCrMemoEntityBuffer.Id
            else
                exit;

        CustLedgerEntry.Modify();
    end;
}