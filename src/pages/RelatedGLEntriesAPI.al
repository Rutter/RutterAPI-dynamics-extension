#if PTE
page 71693 "RTR Related G/L Entries API"
#else
page 71692577 "RTR Related G/L Entries API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Related G/L Entry';
    EntitySetCaption = 'Related G/L Entries';
    DelayedInsert = true;
    DeleteAllowed = false;
    Editable = false;
    EntityName = 'relatedGLEntry';
    EntitySetName = 'relatedGLEntries';
    InsertAllowed = false;
    ModifyAllowed = false;
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "G/L Entry";
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
                field(accountId; Rec."Account Id")
                {
                    Caption = 'Account Id';
                }
                field(accountNumber; Rec."G/L Account No.")
                {
                    Caption = 'Account No.';
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
            }
        }
    }

    trigger OnOpenPage()
    begin
        if Rec.GetFilter("Entry No.") <> '' then begin
            Rec.FindFirst();

            Rec.Reset();
            Rec.SetRange("Document No.", Rec."Document No.");
            Rec.SetRange("Posting Date", Rec."Posting Date");
            Rec.SetRange("Transaction No.", Rec."Transaction No.");
        end else
            Rec.SetRange("Entry No.", 0);
    end;
}