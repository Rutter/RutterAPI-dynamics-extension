#if PTE
tableextension 71693 "RTR Cust. Ledger Entry" extends "Cust. Ledger Entry"
{
    fields
    {
        field(71750; "RTR Journal Id"; Guid)
        {
            Caption = 'Journal Id';
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(71751; "RTR Customer Id"; Guid)
        {
            CalcFormula = Lookup(Customer.SystemId WHERE("No." = FIELD("Customer No.")));
            Caption = 'Customer Id';
            FieldClass = FlowField;
            TableRelation = Customer.SystemId;
            Editable = false;
        }
        field(71752; "RTR Currency Id"; Guid)
        {
            CalcFormula = Lookup(Currency.SystemId WHERE(Code = FIELD("Currency Code")));
            Caption = 'Currency Id';
            FieldClass = FlowField;
            TableRelation = Currency.SystemId;
            Editable = false;
        }
        field(71753; "RTR Sales Invoice Id"; Guid)
        {
            Caption = 'Sales Invoice Id';
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(71754; "RTR Sales Cr. Memo Id"; Guid)
        {
            Caption = 'Sales Cr. Memo Id';
            Editable = false;
            DataClassification = CustomerContent;
        }
        // Published to the blessed sandbox by 22.5.0.21 (FND-2620, PR #26, closed
        // unmerged). BC refuses any upgrade that drops a published field, so it stays
        // declared and unused until that tenant's extension data is deleted.
        field(71755; "RTR Deleted At"; DateTime)
        {
            Caption = 'Deleted At';
            Editable = false;
            DataClassification = CustomerContent;
            ObsoleteState = Pending;
            ObsoleteReason = 'Unused: the FND-2620 delete-marker work was closed unmerged. Declared only to keep upgrades legal on tenants that installed 22.5.0.21.';
            ObsoleteTag = '22.5.0.27';
        }
    }
}
#else
tableextension 71692576 "RTR Cust. Ledger Entry" extends "Cust. Ledger Entry"
{
    fields
    {
        field(71692575; "RTR Journal Id"; Guid)
        {
            Caption = 'Journal Id';
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(71692576; "RTR Customer Id"; Guid)
        {
            CalcFormula = Lookup(Customer.SystemId WHERE("No." = FIELD("Customer No.")));
            Caption = 'Customer Id';
            FieldClass = FlowField;
            TableRelation = Customer.SystemId;
            Editable = false;
        }
        field(71692577; "RTR Currency Id"; Guid)
        {
            CalcFormula = Lookup(Currency.SystemId WHERE(Code = FIELD("Currency Code")));
            Caption = 'Currency Id';
            FieldClass = FlowField;
            TableRelation = Currency.SystemId;
            Editable = false;
        }
        field(71692578; "RTR Sales Invoice Id"; Guid)
        {
            Caption = 'Sales Invoice Id';
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(71692579; "RTR Sales Cr. Memo Id"; Guid)
        {
            Caption = 'Sales Cr. Memo Id';
            Editable = false;
            DataClassification = CustomerContent;
        }
    }
}
#endif