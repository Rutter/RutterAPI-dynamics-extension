#if PTE
tableextension 71693 "RTR Cust. Ledger Entry" extends "Cust. Ledger Entry"
{
    fields
    {
        field(92575; "RTR Journal Id"; Guid)
        {
            Caption = 'Journal Id';
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(92576; "RTR Customer Id"; Guid)
        {
            CalcFormula = Lookup(Customer.SystemId WHERE("No." = FIELD("Customer No.")));
            Caption = 'Customer Id';
            FieldClass = FlowField;
            TableRelation = Vendor.SystemId;
            Editable = false;
        }
        field(92577; "RTR Currency Id"; Guid)
        {
            CalcFormula = Lookup(Currency.SystemId WHERE(Code = FIELD("Currency Code")));
            Caption = 'Currency Id';
            FieldClass = FlowField;
            TableRelation = Currency.SystemId;
            Editable = false;
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
            TableRelation = Vendor.SystemId;
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
    }
}
#endif