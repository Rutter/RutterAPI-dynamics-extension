// https://api.businesscentral.dynamics.com/v2.0/tenantId/production/api/Rutter/RutterAPI/v2.0/companies(companyId)/vendorLedgerEntries?$expand=appliedVendorEntries
#if PTE
page 71694 "RTR Vendor Ledger Entries API"
#else
page 71692575 "RTR Vendor Ledger Entries API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Vendor Ledger Entry';
    EntitySetCaption = 'Vendor Ledger Entries';
    DelayedInsert = true;
    DeleteAllowed = false;
    Editable = false;
    EntityName = 'vendorLedgerEntry';
    EntitySetName = 'vendorLedgerEntries';
    InsertAllowed = false;
    ModifyAllowed = false;
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Vendor Ledger Entry";
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
                field(documentType; Rec."Document Type")
                {
                    Caption = 'Document Type';
                }
                field(externalDocumentNumber; Rec."External Document No.")
                {
                    Caption = 'External Document No.';
                }
                field(paymentMethodCode; Rec."Payment Method Code")
                {
                    Caption = 'Payment Method Code';
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
                field(debitAmount; Rec."Debit Amount")
                {
                    Caption = 'Debit Amount';
                }
                field(creditAmount; Rec."Credit Amount")
                {
                    Caption = 'Credit Amount';
                }
                field(lastModifiedDateTime; Rec.SystemModifiedAt)
                {
                    Caption = 'Last Modified Date';
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
                field(Open; Rec.Open)
                {
                    Caption = 'Open';
                }
                field(remainingAmount; Rec."Remaining Amount")
                {
                    Caption = 'Remaining Amount';
                    ApplicationArea = All;
                }
                part(relatedGLEntries; "RTR Related G/L Entries API")
                {
                    Caption = 'Related G/L Entries';
                    EntityName = 'relatedGLEntry';
                    EntitySetName = 'relatedGLEntries';
                    SubPageLink = "Entry No." = field("Entry No.");
                }
                part(appliedVendorEntries; "RTR Applied Vendor Entries API")
                {
                    Caption = 'Applied Vendor Entries';
                    EntityName = 'appliedVendorEntry';
                    EntitySetName = 'appliedVendorEntries';
                    SubPageLink = "Entry No." = field("Entry No.");
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        GLEntry: Record "G/L Entry";
    begin
        Clear(AccountId);
        if GLEntry.Get(Rec."Entry No.") then begin
            GLEntry.CalcFields("Account Id");
            AccountId := GLEntry."Account Id";
        end
    end;

    var
        AccountId: Guid;
}