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
    }
}
#endif