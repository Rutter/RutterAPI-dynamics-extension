#if PTE
page 71702 "RTR Tax Area Lines API"
#else
page 71692585 "RTR Tax Area Lines API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Tax Area Line';
    EntitySetCaption = 'Tax Area Lines';
    DelayedInsert = true;
    EntityName = 'taxAreaLine';
    EntitySetName = 'taxAreaLines';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Tax Area Line";
    Extensible = false;
    ODataKeyFields = "Tax Area", "Tax Jurisdiction Code";
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field(Tax_Area; Rec."Tax Area")
                {
                    Caption = 'Tax Area';
                }
                field(Tax_Jurisdiction_Code; Rec."Tax Jurisdiction Code")
                {
                    Caption = 'Tax Jurisdiction Code';
                }
                field(Calculation_Order; Rec."Calculation Order")
                {
                    Caption = 'Calculation Order';
                }
            }
        }
    }
}
