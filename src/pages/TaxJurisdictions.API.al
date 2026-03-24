#if PTE
page 71701 "RTR Tax Jurisdictions API"
#else
page 71692584 "RTR Tax Jurisdictions API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Tax Jurisdiction';
    EntitySetCaption = 'Tax Jurisdictions';
    DelayedInsert = true;
    EntityName = 'taxJurisdiction';
    EntitySetName = 'taxJurisdictions';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Tax Jurisdiction";
    Extensible = false;
    ODataKeyFields = Code;
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
                field(Code; Rec.Code)
                {
                    Caption = 'Code';
                }
                field(Description; Rec.Description)
                {
                    Caption = 'Description';
                }
                // field(Default_Sales_and_Use_Tax; Rec."")
                // {
                //     Caption = 'Default Sales and Use Tax';
                // }
                field(Calculate_Tax_on_Tax; Rec."Calculate Tax on Tax")
                {
                    Caption = 'Calculate Tax on Tax';
                }
                field(Report_to_Jurisdiction; Rec."Report-to Jurisdiction")
                {
                    Caption = 'Report-to Jurisdiction';
                }
                field(Country_Region; Rec."Country/Region")
                {
                    Caption = 'Country/Region';
                }
                field(Adjust_for_Payment_Discount; Rec."Adjust for Payment Discount")
                {
                    Caption = 'Adjust for Payment Discount';
                }
            }
        }
    }
}
