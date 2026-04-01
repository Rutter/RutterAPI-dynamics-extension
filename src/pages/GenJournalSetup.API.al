#if PTE
page 71704 "RTR Gen. Jnl. Setup API"
#else
page 71692587 "RTR Gen. Jnl. Setup API"
#endif
{
    APIVersion = 'v2.0';
    EntityName = 'genJournalSetup';
    EntitySetName = 'genJournalSetups';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Gen. Journal Template";
    ODataKeyFields = Name;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = true;
    Editable = true;
    Extensible = false;

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field(name; Rec.Name)
                {
                    Caption = 'Name';
                    Editable = false;
                }
                // Enabling allowVATDifference also ensures Max. VAT Difference Allowed
                // in GL Setup is set to a large value so that users do not error out
                // when Rutter sets a custom tax amount. We only set it if it is currently
                // 0 (unset) to avoid overriding a value the customer has intentionally configured.
                field(allowVATDifference; Rec."Allow VAT Difference")
                {
                    Caption = 'Allow VAT Difference';

                    trigger OnValidate()
                    var
                        GLSetup: Record "General Ledger Setup";
                    begin
                        if Rec."Allow VAT Difference" then begin
                            GLSetup.Get();
                            if GLSetup."Max. VAT Difference Allowed" = 0 then begin
                                GLSetup."Max. VAT Difference Allowed" := 1000000000;
                                GLSetup.Modify();
                            end;
                        end;
                    end;
                }
            }
        }
    }
}
