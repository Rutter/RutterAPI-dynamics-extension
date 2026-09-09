// https://api.businesscentral.dynamics.com/v2.0/tenantId/production/api/Rutter/RutterAPI/v2.0/companies(companyId)/vendorLedgerEntries?$expand=appliedVendorEntries
#if PTE
page 71698 "RTR Cust. Ledger Entries API"
#else
page 71692578 "RTR Cust. Ledger Entries API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Customer Ledger Entry';
    EntitySetCaption = 'Customer Ledger Entries';
    DelayedInsert = true;
    DeleteAllowed = false;
    Editable = false;
    EntityName = 'customerLedgerEntry';
    EntitySetName = 'customerLedgerEntries';
    InsertAllowed = false;
    ModifyAllowed = false;
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Cust. Ledger Entry";
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
                field(customerId; Rec."RTR Customer Id")
                {
                    Caption = 'Customer Id';
                }
                field(salesInvoiceId; Rec."RTR Sales Invoice Id")
                {
                    Caption = 'Sales Invoice Id';
                }
                field(salesCreditMemoId; Rec."RTR Sales Cr. Memo Id")
                {
                    Caption = 'Sales Cr. Memo Id';
                }
                field(customerNumber; Rec."Customer No.")
                {
                    Caption = 'Customer No.';
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
                part(appliedCustomerEntries; "RTR Applied Cust. Entries API")
                {
                    Caption = 'Applied Customer Entries';
                    EntityName = 'appliedCustomerEntry';
                    EntitySetName = 'appliedCustomerEntries';
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

    // Reverses the entry's whole posting transaction — BC has no delete for a posted entry.
    // Mirrors the vendor side (FND-2616) for customer payments (FND-2620).
    //
    // Call via:
    //   POST .../customerLedgerEntries({systemId})/Microsoft.NAV.reverseTransaction
    [ServiceEnabled]
    procedure reverseTransaction(var ActionContext: WebServiceActionContext)
    var
        CustLedgEntryMgt: Codeunit "RTR Cust. Ledger Entry Mgt";
    begin
        CustLedgEntryMgt.ReverseTransaction(Rec."Transaction No.");

        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"RTR Cust. Ledger Entries API");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Get);
    end;

    // Unapplies the entry's open application, if any.
    //
    // Call via:
    //   POST .../customerLedgerEntries({systemId})/Microsoft.NAV.unapplyEntry
    [ServiceEnabled]
    procedure unapplyEntry(var ActionContext: WebServiceActionContext)
    var
        CustLedgEntryMgt: Codeunit "RTR Cust. Ledger Entry Mgt";
    begin
        CustLedgEntryMgt.UnapplyEntry(Rec."Entry No.");

        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"RTR Cust. Ledger Entries API");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Get);
    end;

    // What a posted customer payment actually needs to be undone (unapply + reverse).
    // A customer payment is always applied to an invoice, so plain reversal alone
    // is rejected — unapply first when needed, the same composition the vendor
    // side uses.
    //
    // Call via:
    //   POST .../customerLedgerEntries({systemId})/Microsoft.NAV.unapplyAndReverseTransaction
    [ServiceEnabled]
    procedure unapplyAndReverseTransaction(var ActionContext: WebServiceActionContext)
    var
        CustLedgEntryMgt: Codeunit "RTR Cust. Ledger Entry Mgt";
    begin
        CustLedgEntryMgt.UnapplyAndReverseTransaction(Rec."Entry No.", Rec."Transaction No.");

        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"RTR Cust. Ledger Entries API");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Get);
    end;

    var
        AccountId: Guid;
}