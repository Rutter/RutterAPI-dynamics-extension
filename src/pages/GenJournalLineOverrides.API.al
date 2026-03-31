#if PTE
page 71703 "RTR Gen. Jnl. Overrides API"
#else
page 71692586 "RTR Gen. Jnl. Overrides API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Gen. Journal Line Overrides';
    EntitySetCaption = 'Gen. Journal Line Overrides';
    EntityName = 'genJournalLineOverrides';
    EntitySetName = 'genJournalLineOverrides';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Gen. Journal Line";
    ODataKeyFields = SystemId;
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
                field(id; Rec.SystemId)
                {
                    Caption = 'Id';
                    Editable = false;
                }
                // "VAT Amount" is the underlying storage field for both VAT (non-US) and
                // Sales Tax (US/NA) on Gen. Journal Line — BC decides which label to show
                // in the UI based on localization. One field covers both regions.
                // We bypass Rec.Validate("VAT Amount") because the journal batch context
                // (Allow VAT Difference flag) is not initialized in an API page, causing BC
                // to default max difference to 0. Instead we check the template ourselves.
                field(RTRVATAmountAPI; VATAmt)
                {
                    Caption = 'VAT Amount API';

                    trigger OnValidate()
                    var
                        GenJnlTemplate: Record "Gen. Journal Template";
                        GLSetup: Record "General Ledger Setup";
                        VATDiff: Decimal;
                    begin
                        if not GenJnlTemplate.Get(Rec."Journal Template Name") then
                            Error('Could not find journal template %1.', Rec."Journal Template Name");

                        if not GenJnlTemplate."Allow VAT Difference" then
                            Error('Allow Tax Differences is not enabled on journal template %1.', Rec."Journal Template Name");

                        GLSetup.Get();
                        VATDiff := VATAmt - Rec."VAT Amount";
                        if Abs(VATDiff) > GLSetup."Max. VAT Difference Allowed" then
                            Error('Tax difference %1 exceeds Max. VAT Difference Allowed of %2.', VATDiff, GLSetup."Max. VAT Difference Allowed");

                        Rec."VAT Difference" := VATDiff;
                        Rec."VAT Amount" := VATAmt;
                    end;
                }
            }
        }
    }

    var
        VATAmt: Decimal;
}
