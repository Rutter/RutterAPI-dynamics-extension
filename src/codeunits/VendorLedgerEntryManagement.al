#if PTE
codeunit 71695 "RTR Vendor Ledger Entry Mgt"
#else
codeunit 71692578 "RTR Vendor Ledger Entry Mgt"
#endif
{

    trigger OnRun()
    begin
    end;

    // Reverses everything posted in one transaction — same engine "Process > Reverse Transaction"
    // uses. TransactionNo, not a typed record, so this is reusable for customer entries too.
    procedure ReverseTransaction(TransactionNo: Integer)
    var
        ReversalEntry: Record "Reversal Entry" temporary;
        ReversalPost: Codeunit "Reversal-Post";
    begin
        ReversalEntry.SetHideDialog(true);
        ReversalEntry.SetHideWarningDialogs();
        ReversalEntry.ReverseTransaction(TransactionNo);

        ReversalPost.SetHideDialog(true);
        ReversalPost.Run(ReversalEntry);
    end;

    // Unapplies the entry's open application, if any. Returns whether it did anything.
    procedure UnapplyEntry(EntryNo: Integer): Boolean
    var
        VendLedgEntry: Record "Vendor Ledger Entry";
        DtldVendLedgEntry: Record "Detailed Vendor Ledg. Entry";
        ApplyUnapplyParameters: Record "Apply Unapply Parameters" temporary;
        VendEntryApplyPostedEntries: Codeunit "VendEntry-Apply Posted Entries";
    begin
        DtldVendLedgEntry.SetCurrentKey("Vendor Ledger Entry No.");
        DtldVendLedgEntry.SetRange("Vendor Ledger Entry No.", EntryNo);
        DtldVendLedgEntry.SetRange("Entry Type", DtldVendLedgEntry."Entry Type"::Application);
        DtldVendLedgEntry.SetRange(Unapplied, false);
        if not DtldVendLedgEntry.FindLast() then
            exit(false);

        VendLedgEntry.Get(EntryNo);
        ApplyUnapplyParameters.CopyFromVendLedgEntry(VendLedgEntry);
        VendEntryApplyPostedEntries.PostUnApplyVendor(DtldVendLedgEntry, ApplyUnapplyParameters);
        exit(true);
    end;

    // Unapplying a payment already reverses it, so only reverse if there was nothing to unapply.
    procedure UnapplyAndReverseTransaction(EntryNo: Integer; TransactionNo: Integer)
    begin
        if not UnapplyEntry(EntryNo) then
            ReverseTransaction(TransactionNo);
    end;
}
