#if PTE
page 71709 "RTR Journal Batch Actions API"
#else
page 71692592 "RTR Journal Batch Actions API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Journal Batch Action';
    EntitySetCaption = 'Journal Batch Actions';
    EntityName = 'journalBatchAction';
    EntitySetName = 'journalBatchActions';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Gen. Journal Batch";
    ODataKeyFields = SystemId;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;
    Editable = false;
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
                field(journalTemplateName; Rec."Journal Template Name")
                {
                    Caption = 'Journal Template Name';
                    Editable = false;
                }
                field(code; Rec.Name)
                {
                    Caption = 'Code';
                    Editable = false;
                }
            }
        }
    }

    // Deletes one or more Gen. Journal Lines from this batch in a single
    // atomic call. See JournalLineManagement.al for the mechanism. Returns
    // the number of lines deleted instead of re-fetching the batch, since
    // the batch record itself carries no useful confirmation of what changed.
    //
    // Call via:
    //   POST .../journalBatchActions({systemId})/Microsoft.NAV.deleteLines
    //   Body: { "lineIdsJson": "[\"<lineSystemId1>\",\"<lineSystemId2>\"]" }
    [ServiceEnabled]
    procedure deleteLines(LineIdsJson: Text): Integer
    var
        JournalLineMgt: Codeunit "RTR Journal Line Mgt";
    begin
        exit(JournalLineMgt.DeleteLines(Rec."Journal Template Name", Rec.Name, LineIdsJson));
    end;
}
