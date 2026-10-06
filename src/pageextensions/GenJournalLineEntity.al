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
#if PTE
            // PTE-only test fixtures for createLines custom fields; not in AppSource builds.
            // Table-bound custom field: createLines must set "Print Posted Documents" in the same call.
            field(rtrTestFlag; Rec."Print Posted Documents")
            {
                ApplicationArea = All;
                Visible = false;
            }
            // Page-variable custom field: createLines can't run its trigger, so it must reject it by name.
            field(rtrTestVar; TestVar)
            {
                ApplicationArea = All;
                Visible = false;

                trigger OnValidate()
                begin
                    Rec."Message to Recipient" := CopyStr(UpperCase(TestVar), 1, MaxStrLen(Rec."Message to Recipient"));
                end;
            }
#endif

        }
    }

    var
        Factor: Decimal;
#if PTE
        TestVar: Text[100];
#endif
}