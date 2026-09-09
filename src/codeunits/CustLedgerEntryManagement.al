
#if PTE
codeunit 71696 "RTR Cust. Ledger Entry Mgt"
#else
codeunit 71692579 "RTR Cust. Ledger Entry Mgt"
#endif
{

    trigger OnRun()
    begin
    end;

    // Reverses everything posted in one transaction — same engine "Process > Reverse Transaction"
    // uses. TransactionNo, not a typed record, so this is reusable for vendor entries too.
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
        CustLedgEntry: Record "Cust. Ledger Entry";
        DtldCustLedgEntry: Record "Detailed Cust. Ledg. Entry";
        ApplyUnapplyParameters: Record "Apply Unapply Parameters" temporary;
        CustEntryApplyPostedEntries: Codeunit "CustEntry-Apply Posted Entries";
    begin
        DtldCustLedgEntry.SetCurrentKey("Cust. Ledger Entry No.");
        DtldCustLedgEntry.SetRange("Cust. Ledger Entry No.", EntryNo);
        DtldCustLedgEntry.SetRange("Entry Type", DtldCustLedgEntry."Entry Type"::Application);
        DtldCustLedgEntry.SetRange(Unapplied, false);
        if not DtldCustLedgEntry.FindLast() then
            exit(false);

        CustLedgEntry.Get(EntryNo);
        ApplyUnapplyParameters.CopyFromCustLedgEntry(CustLedgEntry);
        CustEntryApplyPostedEntries.PostUnApplyCustomer(DtldCustLedgEntry, ApplyUnapplyParameters);
        exit(true);
    end;

    // Unapplying a payment already reverses it, so only reverse if there was nothing to unapply.
    // Stamps the durable delete marker afterwards: the resulting open-unapplied entry is
    // otherwise indistinguishable from a live one (FND-2620). Mirrors the vendor side (FND-2616).
    procedure UnapplyAndReverseTransaction(EntryNo: Integer; TransactionNo: Integer)
    var
        CustLedgEntry: Record "Cust. Ledger Entry";
    begin
        if not UnapplyEntry(EntryNo) then
            ReverseTransaction(TransactionNo);

        CustLedgEntry.Get(EntryNo);
        CustLedgEntry."RTR Deleted At" := CurrentDateTime;
        CustLedgEntry.Modify();
    end;
}
