#if PTE
tableextension 71692 "RTR Vendor Ledger Entry" extends "Vendor Ledger Entry"
{
    fields
    {
        field(92575; "RTR Journal Id"; Guid)
        {
            Caption = 'Journal Id';
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(92576; "RTR Vendor Id"; Guid)
        {
            CalcFormula = Lookup(Vendor.SystemId WHERE("No." = FIELD("Vendor No.")));
            Caption = 'Vendor Id';
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
tableextension 71692575 "RTR Vendor Ledger Entry" extends "Vendor Ledger Entry"
{
    fields
    {
        field(71692575; "RTR Journal Id"; Guid)
        {
            Caption = 'Journal Id';
            Editable = false;
            DataClassification = CustomerContent;
        }
        field(71692576; "RTR Vendor Id"; Guid)
        {
            CalcFormula = Lookup(Vendor.SystemId WHERE("No." = FIELD("Vendor No.")));
            Caption = 'Vendor Id';
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