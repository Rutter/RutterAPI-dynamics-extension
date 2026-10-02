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
                field(RTRVATAmountAPI; VATAmt)
                {
                    Caption = 'VAT Amount API';

                    trigger OnValidate()
                    var
                        JournalLineMgt: Codeunit "RTR Journal Line Mgt";
                    begin
                        JournalLineMgt.ApplyVatAmountOverride(Rec, VATAmt);
                    end;
                }
                // Deferred here because BC validates VAT Bus. Posting Group before
                // Gen. Posting Type when both are set in the same request.
                field(RTRVatBusPostingGroupAPI; VatBusPostingGroupAPI)
                {
                    Caption = 'VAT Bus. Posting Group API';

                    trigger OnValidate()
                    begin
                        Rec.Validate("VAT Bus. Posting Group", VatBusPostingGroupAPI);
                    end;
                }
                field(RTRVatProdPostingGroupAPI; VatProdPostingGroupAPI)
                {
                    Caption = 'VAT Prod. Posting Group API';

                    trigger OnValidate()
                    begin
                        Rec.Validate("VAT Prod. Posting Group", VatProdPostingGroupAPI);
                    end;
                }
            }
        }
    }

    var
        VATAmt: Decimal;
        VatBusPostingGroupAPI: Code[20];
        VatProdPostingGroupAPI: Code[20];
}
