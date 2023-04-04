tableextension 51370 "RUT Vendor Ledger Entry" extends "Vendor Ledger Entry"
{
    fields
    {
        field(51370; "RUT Vendor Id"; Guid)
        {
            CalcFormula = Lookup(Vendor.SystemId WHERE("No." = FIELD("Vendor No.")));
            Caption = 'Vendor Id';
            FieldClass = FlowField;
            TableRelation = Vendor.SystemId;
            Editable = false;
        }
        field(51371; "RUT Currency Id"; Guid)
        {
            CalcFormula = Lookup(Currency.SystemId WHERE(Code = FIELD("Currency Code")));
            Caption = 'Currency Id';
            FieldClass = FlowField;
            TableRelation = Currency.SystemId;
            Editable = false;
        }
        field(51372; "RUT Account Id"; Guid)
        {
            CalcFormula = Lookup("G/L Entry"."Account Id" WHERE("Entry No." = field("Entry No.")));
            Caption = 'Account Id';
            FieldClass = FlowField;
            TableRelation = "G/L Account".SystemId;
            Editable = false;
        }
    }
}

