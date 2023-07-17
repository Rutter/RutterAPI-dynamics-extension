#if PTE
pageextension 71692 "RTR Gen. Journal Line Entity" extends "Gen. Journal Line Entity"
#else
pageextension 71692575 "RTR Gen. Journal Line Entity" extends "Gen. Journal Line Entity"
#endif
{
    layout
    {
        addlast(Group)
        {
            field(RTRCurrencyFactorAPI; Factor)
            {
                Caption = 'Currency Factor API';
                DecimalPlaces = 0 : 15;
                ApplicationArea = All;
                Visible = false;

                trigger OnValidate()
                begin
                    if GuiAllowed then
                        Error('');

                    Rec.Validate("Currency Factor", Factor);
                end;
            }
        }
    }

    var
        Factor: Decimal;
}