#if PTE
page 71697 "RTR Tax Areas API"
#else
page 71692581 "RTR Tax Areas API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Tax Area';
    EntitySetCaption = 'Tax Areas';
    DelayedInsert = true;
    EntityName = 'taxArea';
    EntitySetName = 'taxAreas';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Tax Area";
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

            }
        }
    }
}
