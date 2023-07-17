#if PTE
codeunit 71693 "RTR Rutter Management"
#else
codeunit 71692575 "RTR Rutter Management"
#endif
{
    trigger OnRun()
    begin

    end;

    [EventSubscriber(ObjectType::Table, Database::"Vendor Ledger Entry", 'OnAfterCopyVendLedgerEntryFromGenJnlLine', '', false, false)]
    local procedure VendLedgerEntryOnAfterCopyVendLedgerEntryFromGenJnlLine(var VendorLedgerEntry: Record "Vendor Ledger Entry"; GenJournalLine: Record "Gen. Journal Line")
    begin
        VendorLedgerEntry."RTR Journal Id" := GenJournalLine.SystemId;
    end;
}