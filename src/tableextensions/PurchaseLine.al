#if PTE
tableextension 71694 "RTR Purchase Line" extends "Purchase Line"
#else
tableextension 71692577 "RTR Purchase Line" extends "Purchase Line"
#endif
{
    trigger OnBeforeDelete()
    var
        TaxAmtDiffRef: RecordRef;
    begin
        // BC's OnDelete trigger on "Purchase Line" shows a confirmation dialog —
        // which the API cannot handle (Application_CallbackNotAllowed) — when:
        //   • Rec."VAT Difference" ≠ 0 for the line being deleted, or
        //   • Sales Tax Amount Difference records (Table 10012) exist for the document.
        //
        // OnBeforeDelete fires at the table data layer immediately before the base
        // table OnDelete trigger, and shares the same Rec instance.  Zeroing the
        // field in-memory here prevents the dialog check in OnDelete from firing.
        // No Modify() needed — the record is about to be deleted and the in-memory
        // change is visible to the base table trigger via the shared Rec.
        Rec."VAT Difference" := 0;
        Rec."Amount Including VAT" := Rec.Amount;

        // Clear all Sales Tax Amount Difference records (Table 10012) for the
        // document.  BC checks for these at the document level during line deletion:
        // any record for the document triggers the dialog regardless of which line
        // is being deleted.  Clearing unconditionally is safe — the records are
        // rebuilt by RTRVATAmountAPI OnValidate when tax is re-applied to the
        // remaining lines.  Table 10012 is NA-only; TryOpenSalesTaxAmtDiffTable
        // silently exits in other localizations.
        if TryOpenSalesTaxAmtDiffTable(TaxAmtDiffRef) then begin
            TaxAmtDiffRef.Field(2).SetRange(1); // Document Product Area = Purchase
            TaxAmtDiffRef.Field(1).SetRange(2); // Document Type = Invoice
            TaxAmtDiffRef.Field(3).SetRange(Rec."Document No.");
            TaxAmtDiffRef.DeleteAll();
            TaxAmtDiffRef.Close();
        end;
    end;

    // Tries to open the Sales Tax Amount Difference table (10012).
    // Returns false in non-NA localizations where the table does not exist.
    [TryFunction]
    local procedure TryOpenSalesTaxAmtDiffTable(var RecRef: RecordRef)
    begin
        RecRef.Open(10012);
    end;
}
