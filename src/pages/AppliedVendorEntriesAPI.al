#if PTE
page 71696 "RTR Applied Vendor Entries API"
#else
page 71692576 "RTR Applied Vendor Entries API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Applied Vendor Entry';
    EntitySetCaption = 'Applied Vendor Entries';
    DelayedInsert = true;
    DeleteAllowed = false;
    Editable = false;
    EntityName = 'appliedVendorEntry';
    EntitySetName = 'appliedVendorEntries';
    InsertAllowed = false;
    ModifyAllowed = false;
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Vendor Ledger Entry";
    SourceTableTemporary = true;
    Extensible = false;
    ODataKeyFields = SystemId;

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
                field(entryNumber; Rec."Entry No.")
                {
                    Caption = 'Entry No.';
                    Editable = false;
                }
                field(postingDate; Rec."Posting Date")
                {
                    Caption = 'Posting Date';
                }
                field(documentNumber; Rec."Document No.")
                {
                    Caption = 'Document No.';
                }
                field(externalDocumentNumber; Rec."External Document No.")
                {
                    Caption = 'External Document No.';
                }
                field(documentType; Rec."Document Type")
                {
                    Caption = 'Document Type';
                }
                field(vendorId; Rec."RTR Vendor Id")
                {
                    Caption = 'Vendor Id';
                }
                field(vendorNumber; Rec."Vendor No.")
                {
                    Caption = 'Vendor No.';
                }
                field(description; Rec.Description)
                {
                    Caption = 'Description';
                }
                field(amount; Rec.Amount)
                {
                    Caption = 'Amount';
                }
                field(amountLCY; Rec."Amount (LCY)")
                {
                    Caption = 'Amount (LCY)';
                }
                field(originalAmount; Rec."Original Amount")
                {
                    Caption = 'Original Amount';
                }
                field(originalAmountLCY; Rec."Original Amt. (LCY)")
                {
                    Caption = 'Original Amount (LCY)';
                }
                field(debitAmount; Rec."Debit Amount")
                {
                    Caption = 'Debit Amount';
                }
                field(creditAmount; Rec."Credit Amount")
                {
                    Caption = 'Credit Amount';
                }
                field(closedByAmount; Rec."Closed by Amount")
                {
                    Caption = 'Closed by Amount';
                }
                field(closedByCurrencyCode; Rec."Closed by Currency Code")
                {
                    Caption = 'Closed by Currency Code';
                }
                field(lastModifiedDateTime; Rec.SystemModifiedAt)
                {
                    Caption = 'Last Modified Date';
                }
                field(Open; Rec.Open)
                {
                    Caption = 'Open';
                }
                field(appliedAmount; TempVendLedgEntryFCY."Amount to Apply")
                {
                    Caption = 'Applied Amount';
                    ApplicationArea = All;
                }
                field(appliedAmountLCY; Rec."Amount to Apply")
                {
                    Caption = 'Applied Amount (LCY)';
                    ApplicationArea = All;
                }
                field(remainingAmountLCY; Rec."Remaining Amt. (LCY)")
                {
                    Caption = 'Remaining Amount (LCY)';
                    ApplicationArea = All;
                }
                field(remainingAmount; Rec."Remaining Amount")
                {
                    Caption = 'Remaining Amount';
                    ApplicationArea = All;
                }
                field(currencyCode; Rec."Currency Code")
                {
                    Caption = 'Currency Code';
                }
                field(currencyId; Rec."RTR Currency Id")
                {
                    Caption = 'Currency Id';
                }
                field(accountId; AccountId)
                {
                    Caption = 'Account Id';
                }
                field(journalId; Rec."RTR Journal Id")
                {
                    Caption = 'Journal Id';
                }
            }
        }
    }

    trigger OnFindRecord(Which: Text): Boolean
    var
        VendLedgEntry: Record "Vendor Ledger Entry";
        EntryApplicationMgt: Codeunit "RTR Entry Application Mgt";
    begin
        VendLedgEntry.SetFilter("Entry No.", Rec.GetFilter("Entry No."));
        VendLedgEntry.FindFirst();

        EntryApplicationMgt.GetAppliedVendEntries(Rec, VendLedgEntry, true);
        EntryApplicationMgt.GetAppliedVendEntries(TempVendLedgEntryFCY, VendLedgEntry, false);

        exit(Rec.FindFirst());
    end;

    trigger OnAfterGetRecord()
    var
        GLEntry: Record "G/L Entry";
    begin
        Clear(AccountId);

        if GLEntry.Get(Rec."Entry No.") then begin
            GLEntry.CalcFields("Account Id");
            AccountId := GLEntry."Account Id";
        end;

        if not TempVendLedgEntryFCY.Get(Rec."Entry No.") then
            Clear(TempVendLedgEntryFCY);
    end;

    var
        TempVendLedgEntryFCY: Record "Vendor Ledger Entry" temporary;
        AccountId: Guid;
}
