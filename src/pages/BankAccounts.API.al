#if PTE
page 71695 "RTR Bank Accounts API"
#else
page 71692580 "RTR Bank Accounts API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Bank Account';
    EntitySetCaption = 'Bank Accounts';
    DelayedInsert = true;
    EntityName = 'bankAccount';
    EntitySetName = 'bankAccounts';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Bank Account";
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
                field(number; Rec."No.")
                {
                    Caption = 'No.';
                }
                field(displayName; Rec.Name)
                {
                    Caption = 'Display Name';
                }
                field(bankAccPostingGroup; Rec."Bank Acc. Posting Group")
                {
                    Caption = 'Bank Acc. Posting Group';
                }
                field(accountId; GLAccount.SystemId)
                {
                    Caption = 'Account Id';
                }
                field(accountNumber; GLAccount."No.")
                {
                    Caption = 'Account No.';
                }
                field(accountName; GLAccount.Name)
                {
                    Caption = 'Account Name';
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        BankAccPostingGroup: Record "Bank Account Posting Group";
    begin
        Clear(GLAccount);
        if BankAccPostingGroup.Get(Rec."Bank Acc. Posting Group") then
            if GLAccount.Get(BankAccPostingGroup.Code) then;
    end;

    var
        GLAccount: Record "G/L Account";
}