#if PTE
codeunit 71694 "RTR Journal Line Mgt"
#else
codeunit 71692577 "RTR Journal Line Mgt"
#endif
{

    trigger OnRun()
    begin
    end;

    // Deletes one or more Gen. Journal Lines from a batch in a single call.
    // Needed because the standard v2.0 API only deletes one line at a time,
    // so a failure partway through today's sequential-DELETE approach leaves
    // some lines deleted and others not, with no way to undo it. Here, if any
    // line id is invalid, the Error() below aborts the whole call and BC
    // rolls back every Delete() already done in this transaction — same
    // all-or-nothing mechanism ApplyCreditMemoToBills relies on.
    procedure DeleteLines(JournalTemplateName: Code[10]; JournalBatchName: Code[10]; LineIdsJson: Text) DeletedCount: Integer
    var
        GenJournalLine: Record "Gen. Journal Line";
        LineIdsArray: JsonArray;
        LineIdToken: JsonToken;
        LineId: Guid;
    begin
        if not LineIdsArray.ReadFrom(LineIdsJson) then
            Error('Invalid line ids payload: could not parse JSON.');

        if LineIdsArray.Count = 0 then
            Error('At least one line id must be provided.');

        foreach LineIdToken in LineIdsArray do begin
            if not Evaluate(LineId, LineIdToken.AsValue().AsText()) then
                Error('Invalid line id: %1.', LineIdToken.AsValue().AsText());

            GenJournalLine.Reset();
            GenJournalLine.SetRange("Journal Template Name", JournalTemplateName);
            GenJournalLine.SetRange("Journal Batch Name", JournalBatchName);
            GenJournalLine.SetRange(SystemId, LineId);
            if not GenJournalLine.FindFirst() then
                Error('Journal line %1 not found in batch %2.', LineId, JournalBatchName);

            GenJournalLine.Delete(true);
            DeletedCount += 1;
        end;
    end;
}
