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
    DeleteAllowed = false;
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
    local procedure WriteTaxAmountDifferences()
    var
        OtherLine: Record "Purchase Line";
        TaxAreaLine2: Record "Tax Area Line";
        TaxDetail2: Record "Tax Detail";
        TaxAmtDiff: Record "Sales Tax Amount Difference";
        TotalDesiredTax: Decimal;
        TotalBaseAmount: Decimal;
        JurisdictionCount: Integer;
        DiffPerJur: Decimal;
        RemainingTax: Decimal;
        JurIdx: Integer;
        CalcTaxPerJur: Decimal;
    begin
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
        TaxAmtDiff.SetRange("Document Product Area", "Sales Tax Document Area"::Purchase);
        TaxAmtDiff.SetRange("Document Type", TaxAmtDiff."Document Type"::Invoice);
        TaxAmtDiff.SetRange("Document No.", Rec."Document No.");
        TaxAmtDiff.DeleteAll();

        if TotalDesiredTax = 0 then
            exit;

        // Count active non-expense jurisdictions for this line's tax area + group.
        TaxAreaLine2.SetRange("Tax Area", Rec."Tax Area Code");
        if not TaxAreaLine2.FindSet() then
            exit;
        repeat
            if FindApplicableTaxDetail(TaxDetail2, TaxAreaLine2."Tax Jurisdiction Code", Rec."Tax Group Code") then
                JurisdictionCount += 1;
        until TaxAreaLine2.Next() = 0;

        if JurisdictionCount = 0 then
            exit;

        // Split TotalDesiredTax evenly across jurisdictions; last absorbs rounding.
        DiffPerJur := Round(TotalDesiredTax / JurisdictionCount, 0.01);
        RemainingTax := TotalDesiredTax;

        TaxAreaLine2.FindSet();
        repeat
            if FindApplicableTaxDetail(TaxDetail2, TaxAreaLine2."Tax Jurisdiction Code", Rec."Tax Group Code") then begin
                JurIdx += 1;
                // Approximate the calculated tax for this jurisdiction using the rate.
                CalcTaxPerJur := TotalBaseAmount * TaxDetail2."Tax Below Maximum" / 100;

                TaxAmtDiff.Init();
                TaxAmtDiff."Document Product Area" := "Sales Tax Document Area"::Purchase;
                TaxAmtDiff."Document Type" := TaxAmtDiff."Document Type"::Invoice;
                TaxAmtDiff."Document No." := Rec."Document No.";
                TaxAmtDiff."Tax Area Code" := Rec."Tax Area Code";
                TaxAmtDiff."Tax Jurisdiction Code" := TaxAreaLine2."Tax Jurisdiction Code";
                TaxAmtDiff."Tax %" := TaxDetail2."Tax Below Maximum";
                TaxAmtDiff."Tax Group Code" := Rec."Tax Group Code";
                TaxAmtDiff."Expense/Capitalize" := false;
                // Tax Type must be "Sales and Use Tax" (0) to match TempSalesTaxAmountLine
                // created by AddPurchLine, which never sets Positive or Tax Type explicitly.
                TaxAmtDiff."Tax Type" := TaxAmtDiff."Tax Type"::"Sales and Use Tax";
                TaxAmtDiff."Use Tax" := Rec."Use Tax";
                TaxAmtDiff.Positive := false;

                if JurIdx = JurisdictionCount then
                    // Last jurisdiction absorbs rounding remainder.
                    TaxAmtDiff."Tax Difference" := RemainingTax - CalcTaxPerJur
                else begin
                    TaxAmtDiff."Tax Difference" := DiffPerJur - CalcTaxPerJur;
                    RemainingTax -= DiffPerJur;
                end;

                TaxAmtDiff.Insert();
            end;
        until TaxAreaLine2.Next() = 0;
    end;

    // Returns true (and populates TaxDetail) if there is an applicable non-expense
    // Sales and Use Tax / Sales Tax Only detail for the given jurisdiction + group.
    // Mirrors the filter used by SalesTaxCalculate.EndSalesTaxCalculation.
    local procedure FindApplicableTaxDetail(var TaxDetail: Record "Tax Detail"; JurisdictionCode: Code[10]; TaxGroupCode: Code[20]): Boolean
    begin
        TaxDetail.Reset();
        TaxDetail.SetRange("Tax Jurisdiction Code", JurisdictionCode);
        TaxDetail.SetFilter("Tax Group Code", '%1|%2', '', TaxGroupCode);
        TaxDetail.SetFilter("Effective Date", '<=%1', WorkDate());
        TaxDetail.SetFilter("Tax Type", '%1|%2',
            TaxDetail."Tax Type"::"Sales and Use Tax",
            TaxDetail."Tax Type"::"Sales Tax Only");
        TaxDetail.SetRange("Expense/Capitalize", false);
        exit(TaxDetail.FindLast());
    end;
}
