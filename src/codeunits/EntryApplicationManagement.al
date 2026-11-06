
#if PTE
codeunit 71692 "RTR Entry Application Mgt"
#else
codeunit 71692576 "RTR Entry Application Mgt"
#endif
{

    trigger OnRun()
    begin
    end;

    // Applies a Credit Memo's Vendor Ledger Entry against one or more Bill
    // (Invoice) entries for the same vendor, using the same codeunit BC's own
    // "Post Application" action calls for applying two already-posted entries.
    // Needed because the standard v2.0 API can't do this reliably: appliesToInvoiceId
    // rejects Credit Memo docs, and applyVendorEntries silently drops the
    // application when driven via PATCH.
    procedure ApplyCreditMemoToBills(CreditMemoVendLedgEntry: Record "Vendor Ledger Entry"; BillsJson: Text)
    var
        TempMarkedBill: Record "Vendor Ledger Entry" temporary;
        ApplyUnapplyParameters: Record "Apply Unapply Parameters" temporary;
        VendEntryApplyPostedEntries: Codeunit "VendEntry-Apply Posted Entries";
        TotalAmountToApply: Decimal;
        ApplyId: Code[50];
    begin
        if CreditMemoVendLedgEntry."Document Type" <> CreditMemoVendLedgEntry."Document Type"::"Credit Memo" then
            Error('Vendor Ledger Entry %1 is not a Credit Memo.', CreditMemoVendLedgEntry."Entry No.");

        if not CreditMemoVendLedgEntry.Open then
            Error('Credit Memo %1 is not open.', CreditMemoVendLedgEntry."Document No.");

        ApplyId := Format(CreditMemoVendLedgEntry."Entry No.");
        TotalAmountToApply := MarkBillsForApplication(CreditMemoVendLedgEntry, 'Credit Memo', BillsJson, ApplyId, false, TempMarkedBill);

        // Apply() silently no-ops if the anchor's own Amount to Apply is 0.
        CreditMemoVendLedgEntry."Applies-to ID" := ApplyId;
        CreditMemoVendLedgEntry."Amount to Apply" := TotalAmountToApply;
        CreditMemoVendLedgEntry.Modify();

        ApplyUnapplyParameters.CopyFromVendLedgEntry(CreditMemoVendLedgEntry);
        VendEntryApplyPostedEntries.Apply(CreditMemoVendLedgEntry, ApplyUnapplyParameters);
    end;

    // Posts a payment line and applies exact amounts to several bills (the API only applies full balances).
    // One transaction: any Error() here also rolls back the posted payment.
    procedure PostPaymentAndApplyToBills(JournalTemplateName: Code[10]; JournalBatchName: Code[10]; LineIdText: Text; BillsJson: Text) PaymentEntryId: Text
    var
        GenJournalLine: Record "Gen. Journal Line";
        PaymentVendLedgEntry: Record "Vendor Ledger Entry";
        BillVendLedgEntry: Record "Vendor Ledger Entry";
        TempMarkedBill: Record "Vendor Ledger Entry" temporary;
        ApplyUnapplyParameters: Record "Apply Unapply Parameters" temporary;
        VendEntryApplyPostedEntries: Codeunit "VendEntry-Apply Posted Entries";
        JournalLineMgt: Codeunit "RTR Journal Line Mgt";
        SuppressApplyCommit: Codeunit "RTR Suppress Apply Commit";
        RemainingBefore: Dictionary of [Integer, Decimal];
        LineId: Guid;
        LastEntryNo: Integer;
        TotalAmountToApply: Decimal;
        ApplyId: Code[50];
    begin
        if not Evaluate(LineId, LineIdText) then
            Error('Invalid line id: %1.', LineIdText);

        GenJournalLine.SetRange("Journal Template Name", JournalTemplateName);
        GenJournalLine.SetRange("Journal Batch Name", JournalBatchName);
        GenJournalLine.SetRange(SystemId, LineId);
        if not GenJournalLine.FindFirst() then
            Error('Journal line %1 not found in batch %2.', LineId, JournalBatchName);

        if GenJournalLine."Account Type" <> GenJournalLine."Account Type"::Vendor then
            Error('Journal line %1 is not a vendor line.', LineId);
        if GenJournalLine."Document Type" <> GenJournalLine."Document Type"::Payment then
            Error('Journal line %1 is not a payment.', LineId);
        if GenJournalLine.Amount <= 0 then
            Error('Journal line %1 amount must be greater than zero.', LineId);
        // A native application would post with the line and ignore our per-bill amounts.
        if (GenJournalLine."Applies-to Doc. No." <> '') or (GenJournalLine."Applies-to ID" <> '') then
            Error('Journal line %1 must not have Applies-to set.', LineId);

        // The payment entry doesn't exist yet, so bills are checked against the line's vendor and
        // currency, and marked with the line's unique id, before anything is posted.
        ApplyId := Format(LineId, 0, 4);
        PaymentVendLedgEntry."Vendor No." := GenJournalLine."Account No.";
        PaymentVendLedgEntry."Currency Code" := GenJournalLine."Currency Code";
        TotalAmountToApply := MarkBillsForApplication(PaymentVendLedgEntry, 'Payment', BillsJson, ApplyId, true, TempMarkedBill);

        if TotalAmountToApply <> GenJournalLine.Amount then
            Error('Bill amounts (%1) must add up to the payment amount (%2).', TotalAmountToApply, GenJournalLine.Amount);

        TempMarkedBill.FindSet();
        repeat
            if TempMarkedBill."Applies-to ID" <> '' then
                Error('Bill %1 is already marked for another application (%2).', TempMarkedBill."Document No.", TempMarkedBill."Applies-to ID");
            // FlowFields don't survive a temporary table, so read the live balance here.
            BillVendLedgEntry.Get(TempMarkedBill."Entry No.");
            BillVendLedgEntry.CalcFields("Remaining Amount");
            if TempMarkedBill."Amount to Apply" > Abs(BillVendLedgEntry."Remaining Amount") then
                Error('Bill %1 amountToApply (%2) is more than its remaining amount (%3).', TempMarkedBill."Document No.", TempMarkedBill."Amount to Apply", Abs(BillVendLedgEntry."Remaining Amount"));
            RemainingBefore.Add(TempMarkedBill."Entry No.", BillVendLedgEntry."Remaining Amount");
        until TempMarkedBill.Next() = 0;

        PaymentVendLedgEntry.Reset();
        if PaymentVendLedgEntry.FindLast() then
            LastEntryNo := PaymentVendLedgEntry."Entry No.";

        JournalLineMgt.PostLines(JournalTemplateName, JournalBatchName, StrSubstNo('["%1"]', Format(LineId, 0, 4)));

        PaymentVendLedgEntry.Reset();
        PaymentVendLedgEntry.SetFilter("Entry No.", '>%1', LastEntryNo);
        PaymentVendLedgEntry.SetRange("Vendor No.", GenJournalLine."Account No.");
        PaymentVendLedgEntry.SetRange("Document Type", PaymentVendLedgEntry."Document Type"::Payment);
        PaymentVendLedgEntry.SetRange("Document No.", GenJournalLine."Document No.");
        if PaymentVendLedgEntry.Count <> 1 then
            Error('Expected one posted payment entry for document %1, found %2.', GenJournalLine."Document No.", PaymentVendLedgEntry.Count);
        PaymentVendLedgEntry.FindFirst();

        PaymentVendLedgEntry."Applies-to ID" := ApplyId;
        PaymentVendLedgEntry."Amount to Apply" := TotalAmountToApply;
        PaymentVendLedgEntry.Modify();

        // Apply() commits on its own; suppressed so the checks below can still roll everything back.
        BindSubscription(SuppressApplyCommit);
        ApplyUnapplyParameters.CopyFromVendLedgEntry(PaymentVendLedgEntry);
        if not VendEntryApplyPostedEntries.Apply(PaymentVendLedgEntry, ApplyUnapplyParameters) then
            Error('Business Central declined the application of payment %1.', PaymentVendLedgEntry."Document No.");
        UnbindSubscription(SuppressApplyCommit);

        // BC can close a bill in full instead (payment discount, tolerance); reject that.
        TempMarkedBill.FindSet();
        repeat
            BillVendLedgEntry.Get(TempMarkedBill."Entry No.");
            BillVendLedgEntry.CalcFields("Remaining Amount");
            if BillVendLedgEntry."Remaining Amount" - RemainingBefore.Get(TempMarkedBill."Entry No.") <> TempMarkedBill."Amount to Apply" then
                Error('Bill %1 was applied %2 instead of %3.', TempMarkedBill."Document No.", BillVendLedgEntry."Remaining Amount" - RemainingBefore.Get(TempMarkedBill."Entry No."), TempMarkedBill."Amount to Apply");
        until TempMarkedBill.Next() = 0;

        PaymentVendLedgEntry.Get(PaymentVendLedgEntry."Entry No.");
        PaymentVendLedgEntry.CalcFields("Remaining Amount");
        if PaymentVendLedgEntry."Remaining Amount" <> 0 then
            Error('Payment %1 was not fully applied; %2 remains.', PaymentVendLedgEntry."Document No.", PaymentVendLedgEntry."Remaining Amount");

        PaymentEntryId := LowerCase(Format(PaymentVendLedgEntry.SystemId, 0, 4));
    end;

    // Checks each bill against the anchor and marks it with ApplyId; TempMarkedBill keeps the pre-mark copy.
    // ByBillId: bills come as purchase invoice ids, resolved like vendorPayments.appliesToInvoiceId.
    local procedure MarkBillsForApplication(AnchorVendLedgEntry: Record "Vendor Ledger Entry"; AnchorLabel: Text; BillsJson: Text; ApplyId: Code[50]; ByBillId: Boolean; var TempMarkedBill: Record "Vendor Ledger Entry" temporary) TotalAmountToApply: Decimal
    var
        BillVendLedgEntry: Record "Vendor Ledger Entry";
        PurchInvHeader: Record "Purch. Inv. Header";
        PurchInvAggregator: Codeunit "Purch. Inv. Aggregator";
        BillsArray: JsonArray;
        BillToken: JsonToken;
        BillObject: JsonObject;
        DocNoToken: JsonToken;
        BillIdToken: JsonToken;
        AmountToken: JsonToken;
        DocumentNumber: Code[20];
        BillId: Text;
        BillGuid: Guid;
        AmountToApply: Decimal;
    begin
        if not BillsArray.ReadFrom(BillsJson) then
            Error('Invalid bills payload: could not parse JSON.');

        if BillsArray.Count = 0 then
            Error('At least one bill must be provided.');

        foreach BillToken in BillsArray do begin
            BillObject := BillToken.AsObject();
            if ByBillId then begin
                if not BillObject.Get('billId', BillIdToken) then
                    Error('Each bill entry requires a billId.');
                BillId := BillIdToken.AsValue().AsText();
                // The lookup uses SetFilter, so only a parsed Guid may reach it.
                if not Evaluate(BillGuid, BillId) then
                    Error('Bill %1 is not a valid purchase invoice id.', BillId);
                PurchInvHeader.Reset();
                if not PurchInvAggregator.GetPurchaseInvoiceHeaderFromId(Format(BillGuid), PurchInvHeader) then
                    Error('Bill %1 is not a posted purchase invoice.', BillId);
                if not BillVendLedgEntry.Get(PurchInvHeader."Vendor Ledger Entry No.") then
                    Error('Bill %1 has no vendor ledger entry.', PurchInvHeader."No.");
                if (BillVendLedgEntry."Vendor No." <> AnchorVendLedgEntry."Vendor No.") or
                   (BillVendLedgEntry."Document Type" <> BillVendLedgEntry."Document Type"::Invoice)
                then
                    Error('Bill %1 is not an invoice for vendor %2.', PurchInvHeader."No.", AnchorVendLedgEntry."Vendor No.");
                DocumentNumber := BillVendLedgEntry."Document No.";
            end else
                if not BillObject.Get('documentNumber', DocNoToken) then
                    Error('Each bill entry requires a documentNumber.');
            if not BillObject.Get('amountToApply', AmountToken) then
                Error('Each bill entry requires an amountToApply.');

            if not ByBillId then
                DocumentNumber := CopyStr(DocNoToken.AsValue().AsText(), 1, MaxStrLen(DocumentNumber));
            AmountToApply := AmountToken.AsValue().AsDecimal();

            if AmountToApply <= 0 then
                Error('Bill %1 amountToApply must be greater than zero.', DocumentNumber);

            if not ByBillId then begin
                BillVendLedgEntry.Reset();
                BillVendLedgEntry.SetRange("Vendor No.", AnchorVendLedgEntry."Vendor No.");
                BillVendLedgEntry.SetRange("Document Type", BillVendLedgEntry."Document Type"::Invoice);
                BillVendLedgEntry.SetRange("Document No.", DocumentNumber);
                if not BillVendLedgEntry.FindFirst() then
                    Error('Bill %1 not found for vendor %2.', DocumentNumber, AnchorVendLedgEntry."Vendor No.");
            end;
            if not BillVendLedgEntry.Open then
                Error('Bill %1 is not open.', DocumentNumber);

            if BillVendLedgEntry."Currency Code" <> AnchorVendLedgEntry."Currency Code" then
                Error('Bill %1 currency (%2) does not match %3 currency (%4).', DocumentNumber, BillVendLedgEntry."Currency Code", AnchorLabel, AnchorVendLedgEntry."Currency Code");

            TempMarkedBill := BillVendLedgEntry;
            TempMarkedBill."Amount to Apply" := AmountToApply;
            if not TempMarkedBill.Insert() then
                Error('Bill %1 was specified more than once.', DocumentNumber);

            BillVendLedgEntry."Applies-to ID" := ApplyId;
            BillVendLedgEntry."Amount to Apply" := -AmountToApply;
            BillVendLedgEntry.Modify();

            TotalAmountToApply += AmountToApply;
        end;
    end;

    procedure GetAppliedCustEntries(var AppliedCustLedgEntry: Record "Cust. Ledger Entry" temporary; CustLedgEntry: Record "Cust. Ledger Entry"; UseLCY: Boolean)
    var
        DtldCustLedgEntry: Record "Detailed Cust. Ledg. Entry";
        PmtDtldCustLedgEntry: Record "Detailed Cust. Ledg. Entry";
        PmtCustLedgEntry: Record "Cust. Ledger Entry";
        ClosingCustLedgEntry: Record "Cust. Ledger Entry";
        AmountToApply: Decimal;
    begin
        // Temporary Table, AppliedCustLedgEntry, to be filled in with everything that CustLedgEntry applied to.
        // Note that within AppliedCustLedgEntry, the "Amount to Apply" field will be filled in with the Amount Applied.
        // IF UseLCY is TRUE, Amount Applied will be in LCY, else it will be in the application currency
        AppliedCustLedgEntry.Reset();
        AppliedCustLedgEntry.DeleteAll();

        DtldCustLedgEntry.SetCurrentKey("Cust. Ledger Entry No.");
        DtldCustLedgEntry.SetRange("Cust. Ledger Entry No.", CustLedgEntry."Entry No.");
        DtldCustLedgEntry.SetRange("Entry Type", DtldCustLedgEntry."Entry Type"::Application);
        DtldCustLedgEntry.SetRange(Unapplied, false);
        if DtldCustLedgEntry.Find('-') then
            repeat
                PmtDtldCustLedgEntry.SetFilter("Cust. Ledger Entry No.", '<>%1', CustLedgEntry."Entry No.");
                PmtDtldCustLedgEntry.SetRange("Entry Type", DtldCustLedgEntry."Entry Type"::Application);
                PmtDtldCustLedgEntry.SetRange("Transaction No.", DtldCustLedgEntry."Transaction No.");
                PmtDtldCustLedgEntry.SetRange("Application No.", DtldCustLedgEntry."Application No.");
                PmtDtldCustLedgEntry.SetRange("Customer No.", DtldCustLedgEntry."Customer No.");
                OnGetAppliedCustEntriesOnAfterFilterPmtDtldCustLedgEntry(DtldCustLedgEntry, PmtDtldCustLedgEntry);
                PmtDtldCustLedgEntry.FindSet();
                repeat
                    if UseLCY then
                        AmountToApply := -PmtDtldCustLedgEntry."Amount (LCY)"
                    else
                        AmountToApply := -PmtDtldCustLedgEntry.Amount;
                    PmtCustLedgEntry.Get(PmtDtldCustLedgEntry."Cust. Ledger Entry No.");
                    AppliedCustLedgEntry := PmtCustLedgEntry;
                    if AppliedCustLedgEntry.Find() then begin
                        AppliedCustLedgEntry."Amount to Apply" += AmountToApply;
                        AppliedCustLedgEntry.Modify();
                    end else begin
                        AppliedCustLedgEntry := PmtCustLedgEntry;
                        AppliedCustLedgEntry."Amount to Apply" := AmountToApply;
                        if CustLedgEntry."Closed by Entry No." <> 0 then begin
                            ClosingCustLedgEntry.Get(PmtDtldCustLedgEntry."Cust. Ledger Entry No.");
                            if ClosingCustLedgEntry."Closed by Entry No." <> AppliedCustLedgEntry."Entry No." then
                                AppliedCustLedgEntry."Pmt. Disc. Given (LCY)" := 0;
                        end;
                        AppliedCustLedgEntry.Insert();
                    end;
                until PmtDtldCustLedgEntry.Next() = 0;
            until DtldCustLedgEntry.Next() = 0;
    end;

    procedure GetAppliedVendEntries(var AppliedVendLedgEntry: Record "Vendor Ledger Entry" temporary; VendLedgEntry: Record "Vendor Ledger Entry"; UseLCY: Boolean)
    var
        DtldVendLedgEntry: Record "Detailed Vendor Ledg. Entry";
        PmtDtldVendLedgEntry: Record "Detailed Vendor Ledg. Entry";
        PmtVendLedgEntry: Record "Vendor Ledger Entry";
        ClosingVendLedgEntry: Record "Vendor Ledger Entry";
        AmountToApply: Decimal;
        PaymentDiscount: Decimal;
        IsHandled: Boolean;
    begin
        // Temporary Table, AppliedVendLedgEntry, to be filled in with everything that VendLedgEntry applied to.
        // Note that within AppliedVendLedgEntry, the "Amount to Apply" field will be filled in with the Amount Applied.
        // IF UseLCY is TRUE, Amount Applied will be in LCY, else it will be in the application currency
        AppliedVendLedgEntry.Reset();
        AppliedVendLedgEntry.DeleteAll();

        DtldVendLedgEntry.SetCurrentKey("Vendor Ledger Entry No.");
        DtldVendLedgEntry.SetRange("Vendor Ledger Entry No.", VendLedgEntry."Entry No.");
        DtldVendLedgEntry.SetRange("Entry Type", DtldVendLedgEntry."Entry Type"::Application);
        DtldVendLedgEntry.SetRange(Unapplied, false);
        if DtldVendLedgEntry.Find('-') then
            repeat
                PmtDtldVendLedgEntry.SetFilter("Vendor Ledger Entry No.", '<>%1', VendLedgEntry."Entry No.");
                PmtDtldVendLedgEntry.SetRange("Entry Type", DtldVendLedgEntry."Entry Type"::Application);
                PmtDtldVendLedgEntry.SetRange("Transaction No.", DtldVendLedgEntry."Transaction No.");
                PmtDtldVendLedgEntry.SetRange("Application No.", DtldVendLedgEntry."Application No.");
                PmtDtldVendLedgEntry.SetRange("Vendor No.", DtldVendLedgEntry."Vendor No.");
                PmtDtldVendLedgEntry.FindSet();
                repeat
                    IsHandled := false;
                    OnGetAppliedVendEntriesOnBeforePrepareAppliedVendLedgEntry(AppliedVendLedgEntry, VendLedgEntry, UseLCY, PmtDtldVendLedgEntry, IsHandled);
                    if not IsHandled then begin
                        PaymentDiscount := 0;
                        if PmtDtldVendLedgEntry."Posting Date" <= PmtDtldVendLedgEntry."Initial Entry Due Date" then
                            PaymentDiscount := PmtDtldVendLedgEntry."Remaining Pmt. Disc. Possible";
                        if UseLCY then
                            AmountToApply := -PmtDtldVendLedgEntry."Amount (LCY)" - PaymentDiscount
                        else
                            AmountToApply := -PmtDtldVendLedgEntry.Amount - PaymentDiscount;
                        PmtVendLedgEntry.Get(PmtDtldVendLedgEntry."Vendor Ledger Entry No.");
                        AppliedVendLedgEntry := PmtVendLedgEntry;
                        if AppliedVendLedgEntry.Find() then begin
                            AppliedVendLedgEntry."Amount to Apply" += AmountToApply;
                            AppliedVendLedgEntry.Modify();
                        end else begin
                            AppliedVendLedgEntry := PmtVendLedgEntry;
                            AppliedVendLedgEntry."Amount to Apply" := AmountToApply;
                            if VendLedgEntry."Closed by Entry No." <> 0 then begin
                                ClosingVendLedgEntry.Get(PmtDtldVendLedgEntry."Vendor Ledger Entry No.");
                                if ClosingVendLedgEntry."Closed by Entry No." <> AppliedVendLedgEntry."Entry No." then
                                    AppliedVendLedgEntry."Pmt. Disc. Rcd.(LCY)" := 0;
                            end;
                            AppliedVendLedgEntry.Insert();
                        end;
                    end;
                until PmtDtldVendLedgEntry.Next() = 0;
            until DtldVendLedgEntry.Next() = 0;
    end;

    procedure GetAppliedVendorEntries(var
                                          TempAppliedVendLedgEntry: Record "Vendor Ledger Entry" temporary;
                                          VendorNo: Code[20];
                                          PeriodDate: array[2] of Date;
                                          UseLCY: Boolean)
    var
        DtldVendLedgEntry: Record "Detailed Vendor Ledg. Entry";
        PmtDtldVendLedgEntry: Record "Detailed Vendor Ledg. Entry";
        PmtVendLedgEntry: Record "Vendor Ledger Entry";
        ClosingVendLedgEntry: Record "Vendor Ledger Entry";
        VendLedgEntry: Record "Vendor Ledger Entry";
        TempInteger: Record "Integer" temporary;
        AmountToApply: Decimal;
    begin
        TempAppliedVendLedgEntry.Reset();
        TempAppliedVendLedgEntry.DeleteAll();

        VendLedgEntry.SetCurrentKey("Document Type", "Vendor No.", "Posting Date");
        VendLedgEntry.SetRange("Document Type", VendLedgEntry."Document Type"::Payment);
        if VendorNo <> '' then
            VendLedgEntry.SetRange("Vendor No.", VendorNo);
        VendLedgEntry.SetRange("Posting Date", PeriodDate[1], PeriodDate[2]);
        if VendLedgEntry.FindSet() then
            repeat
                DtldVendLedgEntry.SetCurrentKey("Vendor Ledger Entry No.");
                DtldVendLedgEntry.SetRange("Vendor Ledger Entry No.", VendLedgEntry."Entry No.");
                DtldVendLedgEntry.SetRange("Entry Type", DtldVendLedgEntry."Entry Type"::Application);
                DtldVendLedgEntry.SetRange(Unapplied, false);
                if DtldVendLedgEntry.FindSet() then
                    repeat
                        PmtDtldVendLedgEntry.SetFilter("Vendor Ledger Entry No.", '<>%1', VendLedgEntry."Entry No.");
                        PmtDtldVendLedgEntry.SetRange("Entry Type", DtldVendLedgEntry."Entry Type"::Application);
                        if VendorNo <> '' then
                            PmtDtldVendLedgEntry.SetRange("Vendor No.", VendorNo);
                        PmtDtldVendLedgEntry.SetRange("Transaction No.", DtldVendLedgEntry."Transaction No.");
                        PmtDtldVendLedgEntry.SetRange("Application No.", DtldVendLedgEntry."Application No.");
                        PmtDtldVendLedgEntry.FindSet();
                        repeat
                            if TryCacheEntryNo(TempInteger, PmtDtldVendLedgEntry."Entry No.") then begin
                                if UseLCY then
                                    AmountToApply := -PmtDtldVendLedgEntry."Amount (LCY)"
                                else
                                    AmountToApply := -PmtDtldVendLedgEntry.Amount;
                                PmtVendLedgEntry.Get(PmtDtldVendLedgEntry."Vendor Ledger Entry No.");
                                TempAppliedVendLedgEntry := PmtVendLedgEntry;
                                if TempAppliedVendLedgEntry.Find() then begin
                                    TempAppliedVendLedgEntry."Amount to Apply" += AmountToApply;
                                    TempAppliedVendLedgEntry.Modify();
                                end else begin
                                    TempAppliedVendLedgEntry := PmtVendLedgEntry;
                                    TempAppliedVendLedgEntry."Amount to Apply" := AmountToApply;

                                    if VendLedgEntry."Closed by Entry No." <> 0 then begin
                                        ClosingVendLedgEntry.Get(PmtDtldVendLedgEntry."Vendor Ledger Entry No.");
                                        if ClosingVendLedgEntry."Closed by Entry No." <> TempAppliedVendLedgEntry."Entry No." then
                                            TempAppliedVendLedgEntry."Pmt. Disc. Rcd.(LCY)" := 0;
                                        TempAppliedVendLedgEntry."Amount to Apply" +=
                                            GetPaymentDiscount(ClosingVendLedgEntry."Closed by Entry No.", UseLCY);
                                    end;
                                    TempAppliedVendLedgEntry.Insert();
                                end;
                            end;
                        until PmtDtldVendLedgEntry.Next() = 0;
                    until DtldVendLedgEntry.Next() = 0;
            until VendLedgEntry.Next() = 0;
    end;

    local procedure GetPaymentDiscount(ClosingVendLedgEntryNo: Integer; UseLCY: Boolean): Decimal
    var
        DtldVendLedgEntry: Record "Detailed Vendor Ledg. Entry";
    begin
        DtldVendLedgEntry.SetCurrentKey("Vendor Ledger Entry No.", "Entry Type", "Posting Date");
        DtldVendLedgEntry.SetRange("Vendor Ledger Entry No.", ClosingVendLedgEntryNo);
        DtldVendLedgEntry.SetRange("Entry Type", DtldVendLedgEntry."Entry Type"::"Payment Discount");
        DtldVendLedgEntry.SetRange(Unapplied, false);
        if DtldVendLedgEntry.FindFirst() then
            if UseLCY then
                exit(DtldVendLedgEntry."Amount (LCY)")
            else
                exit(DtldVendLedgEntry.Amount);
        exit(0);
    end;

    local procedure TryCacheEntryNo(var TempInteger: Record "Integer" temporary; EntryNo: Integer): Boolean
    begin
        TempInteger.Number := EntryNo;
        exit(TempInteger.Insert());
    end;

    [IntegrationEvent(false, false)]
    local procedure OnGetAppliedCustEntriesOnAfterFilterPmtDtldCustLedgEntry(DtldCustLedgEntry: Record "Detailed Cust. Ledg. Entry"; var PmtDtldCustLedgEntry: Record "Detailed Cust. Ledg. Entry")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnGetAppliedVendEntriesOnBeforePrepareAppliedVendLedgEntry(var AppliedVendLedgEntry: Record "Vendor Ledger Entry" temporary; var VendLedgEntry: Record "Vendor Ledger Entry"; var UseLCY: Boolean; var PmtDtldVendLedgEntry: Record "Detailed Vendor Ledg. Entry"; var IsHandled: Boolean)
    begin
    end;
}

