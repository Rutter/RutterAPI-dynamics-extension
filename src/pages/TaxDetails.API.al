#if PTE
page 71700 "RTR Tax Details API"
#else
page 71692583 "RTR Tax Details API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Tax Detail';
    EntitySetCaption = 'Tax Details';
    DelayedInsert = true;
    EntityName = 'taxDetail';
    EntitySetName = 'taxDetails';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Tax Detail";
    Extensible = false;
    ODataKeyFields = "Tax Jurisdiction Code", "Tax Group Code", "Effective Date";
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
                field(Tax_Jurisdiction_Code; Rec."Tax Jurisdiction Code")
                {
                    Caption = 'Tax Jurisdiction Code';
                }
                field(Tax_Group_Code; Rec."Tax Group Code")
                {
                    Caption = 'Tax Group Code';
                }
                field(Tax_Type; Rec."Tax Type")
                {
                    Caption = 'Tax Type';
                }
                field(Effective_Date; Rec."Effective Date")
                {
                    Caption = 'Effective Date';
                }
                field(Tax_Below_Maximum; Rec."Tax Below Maximum")
                {
                    Caption = 'Tax Below Maximum';
                }
                field(Tax_Above_Maximum; Rec."Tax Above Maximum")
                {
                    Caption = 'Tax Above Maximum';
                }

            }
        }
    }
}
