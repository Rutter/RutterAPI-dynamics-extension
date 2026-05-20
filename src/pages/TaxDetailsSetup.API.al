#if PTE
page 71708 "RTR Tax Details Setup API"
#else
page 71692591 "RTR Tax Details Setup API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Tax Detail Setup';
    EntitySetCaption = 'Tax Details Setup';
    DelayedInsert = true;
    EntityName = 'taxDetailSetup';
    EntitySetName = 'taxDetailsSetup';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "VAT Posting Setup";
    Extensible = false;
    ODataKeyFields = "VAT Bus. Posting Group", "VAT Prod. Posting Group";
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
                field(VAT_Bus_Posting_Group; Rec."VAT Bus. Posting Group")
                {
                    Caption = 'VAT Bus. Posting Group';
                }
                field(VAT_Prod_Posting_Group; Rec."VAT Prod. Posting Group")
                {
                    Caption = 'VAT Prod. Posting Group';
                }
                field(Description; Rec.Description)
                {
                    Caption = 'Description';
                }
                field(VAT_Identifier; Rec."VAT Identifier")
                {
                    Caption = 'VAT Identifier';
                }
                field(VAT_Percent; Rec."VAT %")
                {
                    Caption = 'VAT Percent';
                }
                field(VAT_Calculation_Type; Rec."VAT Calculation Type")
                {
                    Caption = 'VAT Calculation Type';
                }
                field(Blocked; Rec.Blocked)
                {
                    Caption = 'Blocked';
                }
            }
        }
    }
}
