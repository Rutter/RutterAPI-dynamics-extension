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

    // CustLedgerEntry here is the specific ledger entry created for the posted invoice (Microsoft's own
    // parameter doc on Sales-Post calls it "the customer ledger entry we are creating (='the invoice')"),
    // already resolved by BC via FindLast() on Document Type/No. before this event fires. Stamping the
    // invoice's SystemId here (rather than relying on Document No.) keeps the link intact even if the
    // invoice is later renamed, since Document No. on the ledger entry is a point-in-time copy that BC
    // never updates after posting.
    //
    // Deliberately SalesHeader.SystemId (the draft "Sales Header" record already passed into this event),
    // NOT the posted "Sales Invoice Header" (table 112)'s own SystemId. Those are two different physical
    // records with two different SystemIds — but Rutter's own sync reads Sales Invoices through BC's
    // standard salesInvoices API, which is built for draft/posted continuity and keeps returning the
    // DRAFT's SystemId as the invoice's "id" even after posting. Stamping table 112's own SystemId here
    // would silently never match what Rutter's mapper treats as this invoice's platformId.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", 'OnAfterPostSalesDoc', '', false, false)]
    local procedure SalesPostOnAfterPostSalesDoc(var SalesHeader: Record "Sales Header"; var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line"; SalesShptHdrNo: Code[20]; RetRcpHdrNo: Code[20]; SalesInvHdrNo: Code[20]; SalesCrMemoHdrNo: Code[20]; CommitIsSuppressed: Boolean; InvtPickPutaway: Boolean; var CustLedgerEntry: Record "Cust. Ledger Entry"; WhseShip: Boolean; WhseReceiv: Boolean; PreviewMode: Boolean)
    begin
        if SalesInvHdrNo = '' then
            exit;
        if CustLedgerEntry."Entry No." = 0 then
            exit;

        CustLedgerEntry."RTR Sales Invoice Id" := SalesHeader.SystemId;
        CustLedgerEntry.Modify();
    end;
}