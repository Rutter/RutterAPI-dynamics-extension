#if PTE
page 71699 "RTR Applied Cust. Entries API"
#else
page 71692579 "RTR Applied Cust. Entries API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Applied Customer Entry';
    EntitySetCaption = 'Applied Customer Entries';
    DelayedInsert = true;
    DeleteAllowed = false;
    Editable = false;
    EntityName = 'appliedCustomerEntry';
    EntitySetName = 'appliedCustomerEntries';
    InsertAllowed = false;
    ModifyAllowed = false;
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Cust. Ledger Entry";
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
                field(customerId; Rec."RTR Customer Id")
                {
                    Caption = 'Customer Id';
                }
                field(customerNumber; Rec."Customer No.")
                {
                    Caption = 'Customer No.';
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
                field(appliedAmount; TempCustLedgEntryFCY."Amount to Apply")
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
        CustLedgEntry: Record "Cust. Ledger Entry";
        EntryApplicationMgt: Codeunit "RTR Entry Application Mgt";
    begin
        CustLedgEntry.SetFilter("Entry No.", Rec.GetFilter("Entry No."));
        CustLedgEntry.FindFirst();

        EntryApplicationMgt.GetAppliedCustEntries(Rec, CustLedgEntry, true);
        EntryApplicationMgt.GetAppliedCustEntries(TempCustLedgEntryFCY, CustLedgEntry, false);

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

        if not TempCustLedgEntryFCY.Get(Rec."Entry No.") then
            Clear(TempCustLedgEntryFCY);
    end;

    var
        TempCustLedgEntryFCY: Record "Cust. Ledger Entry" temporary;
        AccountId: Guid;
}