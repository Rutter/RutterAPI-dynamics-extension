#if PTE
page 71705 "RTR Purch. Line Overrides API"
#else
page 71692588 "RTR Purch. Line Overrides API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Purchase Line Override';
    EntitySetCaption = 'Purchase Line Overrides';
    EntityName = 'purchaseLineOverride';
    EntitySetName = 'purchaseLineOverrides';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Purchase Line";
    SourceTableView = WHERE("Document Type" = CONST(Invoice));
    ODataKeyFields = SystemId;
    InsertAllowed = false;
    DeleteAllowed = true;
    ModifyAllowed = true;
    Editable = true;
    Extensible = false;

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId)
                {
                    Caption = 'Id';
                    Editable = false;
                }
                // Accepts the desired tax amount for this purchase line.
                // "VAT Amount" is the underlying BC field for both VAT (non-US) and Sales Tax (US/NA).
                // Requires Allow Tax Differences in Purchases & Payables Setup
                // and a sufficiently large Max. VAT Difference Allowed in GL Setup.
                field(RTRVATAmountAPI; TaxAmt)
                {
                    Caption = 'VAT Amount API';

                    trigger OnValidate()
                    var
                        PurchSetup: Record "Purchases & Payables Setup";
                        GLSetup: Record "General Ledger Setup";
                        CurrentTax: Decimal;
                        TaxDiff: Decimal;
                    begin
                        PurchSetup.Get();
                        if not PurchSetup."Allow VAT Difference" then
                            Error('Allow Tax Differences is not enabled in Purchases & Payables Setup.');

                        GLSetup.Get();

                        // VAT Amount is not a stored field on Purchase Line;
                        // it is derived as Amount Including VAT - Amount.
                        CurrentTax := Rec."Amount Including VAT" - Rec.Amount;
                        TaxDiff := TaxAmt - CurrentTax;
                        if Abs(TaxDiff) > GLSetup."Max. VAT Difference Allowed" then
                            Error('Tax difference %1 exceeds Max. VAT Difference Allowed of %2.', TaxDiff, GLSetup."Max. VAT Difference Allowed");

                        Rec."VAT Difference" := TaxDiff;
                        Rec."Amount Including VAT" := Rec.Amount + TaxAmt;

                        // Write per-jurisdiction tax differences so the invoice posts with
                        // the desired tax amount split evenly across all active jurisdictions.
                        // Sales Tax Amount Difference (Table 10012) is read by SalesTaxCalculate
                        // codeunit 398 during EndSalesTaxCalculation and applied additively to
                        // each jurisdiction's calculated tax before posting to the G/L.
                        WriteTaxAmountDifferences();
                    end;
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        TaxAmt := Rec."Amount Including VAT" - Rec.Amount;
    end;

    // Cleanup before deletion (zeroing VAT Difference and clearing Table 10012
    // records) is handled by the RTR Purchase Line tableextension's OnBeforeDelete
    // trigger, which fires at the data layer immediately before the base table
    // OnDelete dialog check.  The page trigger just needs to allow the delete.
    trigger OnDeleteRecord(): Boolean
    begin
        exit(true); // Proceed with deletion.
    end;

    var
        TaxAmt: Decimal;

    // Writes Sales Tax Amount Difference records for the document so that the
    // total desired tax (summed across all lines) is split evenly across active
    // jurisdictions.  Must be called after Rec."Amount Including VAT" is updated
    // so that OtherLine sums reflect the already-patched state of other lines.
    //
    // How BC uses these records (SalesTaxCalculate codeunit 398):
    //   EndSalesTaxCalculation matches each TempSalesTaxAmountLine (per jurisdiction)
    //   against TempTaxAmountDifference (loaded from this table) and sets
    //   TempSalesTaxAmountLine."Tax Difference" := matched record."Tax Difference".
    //   ApplyTaxDifference then adds that difference to the jurisdiction's Tax Amount.
    //   DistTaxOverPurchLines distributes proportionally when Tax Difference <> 0.
    //
    // Tax Difference[i] = (TotalDesiredTax / N) - (TotalBaseAmount * rate[i] / 100)
    // so that each jurisdiction ends up with an equal share of TotalDesiredTax.
    //
    // IMPORTANT: Table 10012 "Sales Tax Amount Difference" and some Tax Detail
    // fields/enums only exist in NA localizations.  We use RecordRef/FieldRef
    // with integer field IDs to avoid compile-time references to NA-only objects
    // so the extension validates for all country/regions on Partner Center.
    local procedure WriteTaxAmountDifferences()
    var
        OtherLine: Record "Purchase Line";
        TaxAreaLine2: Record "Tax Area Line";
        TaxAmtDiffRef: RecordRef;
        TotalDesiredTax: Decimal;
        TotalBaseAmount: Decimal;
        JurisdictionCount: Integer;
        DiffPerJur: Decimal;
        RemainingTax: Decimal;
        JurIdx: Integer;
        CalcTaxPerJur: Decimal;
        TaxBelowMaximum: Decimal;
    begin
        // Sales Tax Amount Difference (Table 10012) is NA-only.
        // Skip entirely for non-NA localizations where the table does not exist.
        if not TryOpenSalesTaxAmtDiffTable(TaxAmtDiffRef) then
            exit;

        // Sum desired tax for the whole document: TaxAmt for this line +
        // existing (already-saved) tax for all other lines.
        TotalDesiredTax := TaxAmt;
        TotalBaseAmount := Rec.Amount;
        OtherLine.SetRange("Document Type", OtherLine."Document Type"::Invoice);
        OtherLine.SetRange("Document No.", Rec."Document No.");
        OtherLine.SetFilter("Line No.", '<>%1', Rec."Line No.");
        if OtherLine.FindSet() then
            repeat
                TotalDesiredTax += OtherLine."Amount Including VAT" - OtherLine.Amount;
                TotalBaseAmount += OtherLine.Amount;
            until OtherLine.Next() = 0;

        // Clear existing records for this document before rewriting.
        // Field 2 = "Document Product Area", 1 = Purchase (Sales Tax Document Area enum)
        // Field 1 = "Document Type", 2 = Invoice
        // Field 3 = "Document No."
        TaxAmtDiffRef.Field(2).SetRange(1);
        TaxAmtDiffRef.Field(1).SetRange(2);
        TaxAmtDiffRef.Field(3).SetRange(Rec."Document No.");
        TaxAmtDiffRef.DeleteAll();
        TaxAmtDiffRef.Close();

        if TotalDesiredTax = 0 then
            exit;

        // Count active non-expense jurisdictions for this line's tax area + group.
        TaxAreaLine2.SetRange("Tax Area", Rec."Tax Area Code");
        if not TaxAreaLine2.FindSet() then
            exit;
        repeat
            if FindApplicableTaxDetail(TaxBelowMaximum, TaxAreaLine2."Tax Jurisdiction Code", Rec."Tax Group Code") then
                JurisdictionCount += 1;
        until TaxAreaLine2.Next() = 0;

        if JurisdictionCount = 0 then
            exit;

        // Split TotalDesiredTax evenly across jurisdictions; last absorbs rounding.
        DiffPerJur := Round(TotalDesiredTax / JurisdictionCount, 0.01);
        RemainingTax := TotalDesiredTax;

        TaxAreaLine2.FindSet();
        repeat
            if FindApplicableTaxDetail(TaxBelowMaximum, TaxAreaLine2."Tax Jurisdiction Code", Rec."Tax Group Code") then begin
                JurIdx += 1;
                // Approximate the calculated tax for this jurisdiction using the rate.
                CalcTaxPerJur := TotalBaseAmount * TaxBelowMaximum / 100;

                // Table 10012 field reference:
                //   1 = Document Type (Option: Quote=0, Order=1, Invoice=2, Credit Memo=3)
                //   2 = Document Product Area (Enum 10012: Sale=0, Purchase=1)
                //   3 = Document No. (Code[20])
                //   5 = Tax Area Code (Code[20])
                //   6 = Tax Jurisdiction Code (Code[10])
                //   7 = Tax Group Code (Code[20])
                //   8 = Tax % (Decimal)
                //   9 = Expense/Capitalize (Boolean)
                //  10 = Tax Type (Option: Sales and Use Tax=0, Excise Tax=1, Sales Tax Only=2)
                //  11 = Use Tax (Boolean)
                //  15 = Tax Difference (Decimal)
                //  16 = Positive (Boolean)
                TaxAmtDiffRef.Open(10012);
                TaxAmtDiffRef.Init();
                TaxAmtDiffRef.Field(2).Value := 1;   // Document Product Area = Purchase
                TaxAmtDiffRef.Field(1).Value := 2;   // Document Type = Invoice
                TaxAmtDiffRef.Field(3).Value := Rec."Document No.";
                TaxAmtDiffRef.Field(5).Value := Rec."Tax Area Code";
                TaxAmtDiffRef.Field(6).Value := TaxAreaLine2."Tax Jurisdiction Code";
                TaxAmtDiffRef.Field(8).Value := TaxBelowMaximum;
                TaxAmtDiffRef.Field(7).Value := Rec."Tax Group Code";
                TaxAmtDiffRef.Field(9).Value := false; // Expense/Capitalize
                // Tax Type = "Sales and Use Tax" (0) to match TempSalesTaxAmountLine
                // created by AddPurchLine.
                TaxAmtDiffRef.Field(10).Value := 0;
                TaxAmtDiffRef.Field(11).Value := Rec."Use Tax";
                TaxAmtDiffRef.Field(16).Value := false; // Positive

                if JurIdx = JurisdictionCount then
                    // Last jurisdiction absorbs rounding remainder.
                    TaxAmtDiffRef.Field(15).Value := RemainingTax - CalcTaxPerJur
                else begin
                    TaxAmtDiffRef.Field(15).Value := DiffPerJur - CalcTaxPerJur;
                    RemainingTax -= DiffPerJur;
                end;

                TaxAmtDiffRef.Insert();
                TaxAmtDiffRef.Close();
            end;
        until TaxAreaLine2.Next() = 0;
    end;

    // Tries to open the Sales Tax Amount Difference table (10012).
    // Returns false in non-NA localizations where the table does not exist.
    [TryFunction]
    local procedure TryOpenSalesTaxAmtDiffTable(var RecRef: RecordRef)
    begin
        RecRef.Open(10012);
    end;

    // Returns true (and outputs TaxBelowMaximum rate) if there is an applicable
    // non-expense Sales and Use Tax / Sales Tax Only detail for the given
    // jurisdiction + group.  Mirrors the filter used by
    // SalesTaxCalculate.EndSalesTaxCalculation.
    //
    // Uses RecordRef for NA-only fields: "Expense/Capitalize" (field 10010)
    // and filters "Tax Type" by ordinal to avoid referencing NA-only enum values.
    local procedure FindApplicableTaxDetail(var TaxBelowMaximum: Decimal; JurisdictionCode: Code[10]; TaxGroupCode: Code[20]): Boolean
    var
        TaxDetail: Record "Tax Detail";
        TaxDetailRef: RecordRef;
        ExpCapFieldRef: FieldRef;
    begin
        TaxDetail.Reset();
        TaxDetail.SetRange("Tax Jurisdiction Code", JurisdictionCode);
        TaxDetail.SetFilter("Tax Group Code", '%1|%2', '', TaxGroupCode);
        TaxDetail.SetFilter("Effective Date", '<=%1', WorkDate());
        // Filter Tax Type by ordinal: 0 = Sales and Use Tax, 2 = Sales Tax Only.
        // Named enum values are NA-only and would fail compilation in other regions.
        TaxDetail.SetFilter("Tax Type", '%1|%2', 0, 2);
        // "Expense/Capitalize" (field 10010) only exists in NA localizations.
        // Apply the filter via FieldRef to avoid a compile-time reference.
        TaxDetailRef.GetTable(TaxDetail);
        if TrySetBooleanFieldRange(TaxDetailRef, 10010, false) then;
        TaxDetailRef.SetTable(TaxDetail);

        if not TaxDetail.FindLast() then
            exit(false);
        TaxBelowMaximum := TaxDetail."Tax Below Maximum";
        exit(true);
    end;

    // Attempts to set a boolean range filter on a RecordRef field.
    // Silently fails if the field does not exist (non-NA localizations).
    [TryFunction]
    local procedure TrySetBooleanFieldRange(var RecRef: RecordRef; FieldNo: Integer; Value: Boolean)
    var
        FldRef: FieldRef;
    begin
        FldRef := RecRef.Field(FieldNo);
        FldRef.SetRange(Value);
    end;
}
