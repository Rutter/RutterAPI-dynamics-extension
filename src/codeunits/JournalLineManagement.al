#if PTE
codeunit 71694 "RTR Journal Line Mgt"
#else
codeunit 71692577 "RTR Journal Line Mgt"
#endif
{

    var
        // Set per line so the value helpers can name the offending line without every one of
        // them taking an index they otherwise have no use for.
        CurrentLineIndex: Integer;

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

    // Posts only these lines via Gen. Jnl.-Post Line directly, unlike Microsoft.NAV.post which
    // posts the whole batch. No Commit() in that codeunit, so a failed line rolls back the rest.
    procedure PostLines(JournalTemplateName: Code[10]; JournalBatchName: Code[10]; LineIdsJson: Text) PostedCount: Integer
    var
        GenJournalLine: Record "Gen. Journal Line";
        GenJournalBatch: Record "Gen. Journal Batch";
        GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line";
        RecordRestrictionMgt: Codeunit "Record Restriction Mgt.";
        LineIdsArray: JsonArray;
        LineIdToken: JsonToken;
        LineId: Guid;
    begin
        if not LineIdsArray.ReadFrom(LineIdsJson) then
            Error('Invalid line ids payload: could not parse JSON.');

        if LineIdsArray.Count = 0 then
            Error('At least one line id must be provided.');

        // Gen. Jnl.-Post Line skips the approval-pending restrictions Gen. Jnl.-Post Batch
        // enforces. The table's OnCheckGenJournalLinePostRestrictions event is OnPrem-scoped
        // (and events can't be raised from an extension), so check the restriction directly.
        GenJournalBatch.Get(JournalTemplateName, JournalBatchName);
        if not RecordRestrictionMgt.CheckRecordHasUsageRestrictions(GenJournalBatch) then
            Error('%1', GetLastErrorText());

        foreach LineIdToken in LineIdsArray do begin
            if not Evaluate(LineId, LineIdToken.AsValue().AsText()) then
                Error('Invalid line id: %1.', LineIdToken.AsValue().AsText());

            GenJournalLine.Reset();
            GenJournalLine.SetRange("Journal Template Name", JournalTemplateName);
            GenJournalLine.SetRange("Journal Batch Name", JournalBatchName);
            GenJournalLine.SetRange(SystemId, LineId);
            if not GenJournalLine.FindFirst() then
                Error('Journal line %1 not found in batch %2.', LineId, JournalBatchName);

            if not RecordRestrictionMgt.CheckRecordHasUsageRestrictions(GenJournalLine) then
                Error('%1', GetLastErrorText());

            GenJnlPostLine.RunWithCheck(GenJournalLine);
            GenJournalLine.Delete(true);
            PostedCount += 1;
        end;
    end;

    // Creates a set of Gen. Journal Lines in one transaction. Replaces the POST-then-PATCH
    // sequence the backend runs against workflowGenJournalLines (page 6407): account type and
    // number, the VAT posting groups and the tax amount override are all applied to the record
    // in a controlled order before Insert(), so BC never observes the mismatched in-between
    // state it rejects today. Any Error() rolls the whole batch back — no compensating deletes.
    // Returns the created lines' SystemIds as a JSON array, in input order.
    procedure CreateLines(JournalTemplateName: Code[10]; JournalBatchName: Code[10]; LinesJson: Text) CreatedIdsJson: Text
    var
        GenJournalLine: Record "Gen. Journal Line";
        LinesArray: JsonArray;
        LineToken: JsonToken;
        CreatedIds: JsonArray;
        LineIndex: Integer;
    begin
        if not LinesArray.ReadFrom(LinesJson) then
            Error('Invalid lines payload: could not parse JSON.');

        if LinesArray.Count = 0 then
            Error('At least one line must be provided.');

        if AnyLineHasTaxOverride(LinesArray) then
            EnableVatDifference(JournalTemplateName);

        foreach LineToken in LinesArray do begin
            LineIndex += 1;
            CreateSingleLine(JournalTemplateName, JournalBatchName, LineToken.AsObject(), LineIndex, GenJournalLine);
            // Lowercased to match what BC's own endpoints return, so callers can compare
            // these ids against page data without normalizing first.
            CreatedIds.Add(LowerCase(Format(GenJournalLine.SystemId, 0, 4)));
        end;

        CreatedIds.WriteTo(CreatedIdsJson);
    end;

    // Applies a custom tax amount to a line. "VAT Amount" is the underlying storage field for
    // both VAT (non-US) and Sales Tax (US/NA) — BC picks the label by localization.
    // We bypass Validate("VAT Amount") because the journal batch context (Allow VAT Difference)
    // is not initialized in an API page, so BC would default the max difference to 0.
    procedure ApplyVatAmountOverride(var GenJournalLine: Record "Gen. Journal Line"; VATAmt: Decimal)
    var
        GenJnlTemplate: Record "Gen. Journal Template";
        GLSetup: Record "General Ledger Setup";
        VATDiff: Decimal;
    begin
        if not GenJnlTemplate.Get(GenJournalLine."Journal Template Name") then
            Error('Could not find journal template %1.', GenJournalLine."Journal Template Name");

        if not GenJnlTemplate."Allow VAT Difference" then
            Error('Allow Tax Differences is not enabled on journal template %1.', GenJournalLine."Journal Template Name");

        GLSetup.Get();
        VATDiff := VATAmt - GenJournalLine."VAT Amount";
        if Abs(VATDiff) > GLSetup."Max. VAT Difference Allowed" then
            Error('Tax difference %1 exceeds Max. VAT Difference Allowed of %2.', VATDiff, GLSetup."Max. VAT Difference Allowed");

        GenJournalLine."VAT Difference" := VATDiff;
        GenJournalLine."VAT Amount" := VATAmt;
        // Keep VAT Base Amount consistent: Amount = VAT Base Amount + VAT Amount.
        // Required for VAT locales (e.g. Canada, EU) where BC enforces this at posting time.
        GenJournalLine."VAT Base Amount" := GenJournalLine.Amount - VATAmt;
    end;

    // Field order here is the point of this codeunit — see the ordering notes inline.
    local procedure CreateSingleLine(JournalTemplateName: Code[10]; JournalBatchName: Code[10]; LineObject: JsonObject; LineIndex: Integer; var GenJournalLine: Record "Gen. Journal Line")
    var
        SnapshotLine: Record "Gen. Journal Line";
        TextValue: Text;
        DecValue: Decimal;
        IntValue: Integer;
        BoolValue: Boolean;
        DateValue: Date;
        GuidValue: Guid;
    begin
        CurrentLineIndex := LineIndex;
        GenJournalLine.Init();
        GenJournalLine."Journal Template Name" := JournalTemplateName;
        GenJournalLine."Journal Batch Name" := JournalBatchName;
        // Stamps "Journal Batch Id" from the batch's SystemId; the standard API pages call it
        // on insert and the backend reads that id back off every created line.
        GenJournalLine.UpdateJournalBatchID();

        if GetInt(LineObject, 'lineNumber', IntValue) then
            GenJournalLine."Line No." := IntValue
        else
            GenJournalLine."Line No." := NextLineNo(JournalTemplateName, JournalBatchName);

        if GetText(LineObject, 'documentNumber', TextValue) then
            GenJournalLine.Validate("Document No.", FitText(TextValue, MaxStrLen(GenJournalLine."Document No.")));
        if GetText(LineObject, 'externalDocumentNumber', TextValue) then
            GenJournalLine.Validate("External Document No.", FitText(TextValue, MaxStrLen(GenJournalLine."External Document No.")));

        // Account type before account number, both validated, in the same transaction: this is
        // what removes the backend's two-step PATCH for bank accounts.
        if GetText(LineObject, 'accountType', TextValue) then
            GenJournalLine.Validate("Account Type", ParseAccountType(TextValue, 'accountType', LineIndex));
        TextValue := ResolveAccountNo(LineObject, 'accountNumber', 'accountId', GenJournalLine."Account Type", LineIndex);
        if TextValue <> '' then begin
            SnapshotLine := GenJournalLine;
            GenJournalLine.Validate("Account No.", FitText(TextValue, MaxStrLen(GenJournalLine."Account No.")));
            // Only when the caller identified the account by id. The OData path assigns
            // Account No. through "Account Id" without validating it, so those lines never
            // picked up the account's defaults; a caller sending a number got them, because
            // BC validates a number. Restoring on both paths would strip defaults from lines
            // that have always had them.
            if not HasValue(LineObject, 'accountNumber') then
                RestoreAccountDefaults(GenJournalLine, SnapshotLine, LineObject);
            // Both paths: the backend's number PATCH resends the description, so it never kept the account name.
            if not HasValue(LineObject, 'description') then
                GenJournalLine.Description := SnapshotLine.Description;
        end;

        // After the account, never before: Due Date is derived here, and validating an account
        // afterwards clears it (page 6407 orders accountNumber then postingDate for the same reason).
        if GetDate(LineObject, 'postingDate', DateValue, LineIndex) then
            GenJournalLine.Validate("Posting Date", DateValue);

        // Page 6407's own position for it: after the account, whose validate overwrites
        // Description with the account name.
        if GetText(LineObject, 'description', TextValue) then
            GenJournalLine.Validate(Description, FitText(TextValue, MaxStrLen(GenJournalLine.Description)));

        if GetText(LineObject, 'balAccountType', TextValue) then
            GenJournalLine.Validate("Bal. Account Type", ParseAccountType(TextValue, 'balAccountType', LineIndex));
        TextValue := ResolveAccountNo(LineObject, 'balAccountNumber', 'balancingAccountId', GenJournalLine."Bal. Account Type", LineIndex);
        if TextValue <> '' then begin
            GenJournalLine.Validate("Bal. Account No.", FitText(TextValue, MaxStrLen(GenJournalLine."Bal. Account No.")));
            // The OData path validated a non-bank bal account while Account No. was still blank, so only
            // the bal account's default dimensions applied; a bank bal is PATCHed in later and gets both.
            if (GenJournalLine."Account No." <> '') and not HasValue(LineObject, 'accountNumber') and
               (GenJournalLine."Bal. Account Type" <> GenJournalLine."Bal. Account Type"::"Bank Account")
            then
                RebuildDimensionsFromBalAccount(GenJournalLine);
        end;

        if GetText(LineObject, 'currencyCode', TextValue) then
            GenJournalLine.Validate("Currency Code", FitText(TextValue, MaxStrLen(GenJournalLine."Currency Code")));

        // Gen. Posting Type first: the VAT posting groups read it to resolve the VAT setup.
        // This is the ordering the backend cannot express in one OData request, which is why
        // it PATCHes the posting groups separately today.
        if GetText(LineObject, 'genPostingType', TextValue) then
            GenJournalLine.Validate("Gen. Posting Type", ParseGenPostingType(TextValue, 'genPostingType', LineIndex));
        // Before VAT Prod.: validating Gen. Prod. Posting Group resets it to the group's default.
        if GetText(LineObject, 'genBusPostingGroup', TextValue) then
            GenJournalLine.Validate("Gen. Bus. Posting Group", FitText(TextValue, MaxStrLen(GenJournalLine."Gen. Bus. Posting Group")));
        if GetText(LineObject, 'genProdPostingGroup', TextValue) then
            GenJournalLine.Validate("Gen. Prod. Posting Group", FitText(TextValue, MaxStrLen(GenJournalLine."Gen. Prod. Posting Group")));
        if GetText(LineObject, 'vatBusPostingGroup', TextValue) then
            GenJournalLine.Validate("VAT Bus. Posting Group", FitText(TextValue, MaxStrLen(GenJournalLine."VAT Bus. Posting Group")));
        if GetText(LineObject, 'RTRVatBusPostingGroupAPI', TextValue) then
            GenJournalLine.Validate("VAT Bus. Posting Group", FitText(TextValue, MaxStrLen(GenJournalLine."VAT Bus. Posting Group")));
        if GetText(LineObject, 'vatProdPostingGroup', TextValue) then
            GenJournalLine.Validate("VAT Prod. Posting Group", FitText(TextValue, MaxStrLen(GenJournalLine."VAT Prod. Posting Group")));
        // The RTR override wins over vatProdPostingGroup: today it is applied in a later PATCH.
        if GetText(LineObject, 'RTRVatProdPostingGroupAPI', TextValue) then
            GenJournalLine.Validate("VAT Prod. Posting Group", FitText(TextValue, MaxStrLen(GenJournalLine."VAT Prod. Posting Group")));

        // Same order on the balancing side: Bal. Gen. Prod. resets Bal. VAT Prod. to its default.
        if GetText(LineObject, 'balGenPostingType', TextValue) then
            GenJournalLine.Validate("Bal. Gen. Posting Type", ParseGenPostingType(TextValue, 'balGenPostingType', LineIndex));
        if GetText(LineObject, 'balGenBusPostingGroup', TextValue) then
            GenJournalLine.Validate("Bal. Gen. Bus. Posting Group", FitText(TextValue, MaxStrLen(GenJournalLine."Bal. Gen. Bus. Posting Group")));
        if GetText(LineObject, 'balGenProdPostingGroup', TextValue) then
            GenJournalLine.Validate("Bal. Gen. Prod. Posting Group", FitText(TextValue, MaxStrLen(GenJournalLine."Bal. Gen. Prod. Posting Group")));
        if GetText(LineObject, 'balVatBusPostingGroup', TextValue) then
            GenJournalLine.Validate("Bal. VAT Bus. Posting Group", FitText(TextValue, MaxStrLen(GenJournalLine."Bal. VAT Bus. Posting Group")));
        if GetText(LineObject, 'balVatProdPostingGroup', TextValue) then
            GenJournalLine.Validate("Bal. VAT Prod. Posting Group", FitText(TextValue, MaxStrLen(GenJournalLine."Bal. VAT Prod. Posting Group")));

        if GetText(LineObject, 'taxAreaCode', TextValue) then
            GenJournalLine.Validate("Tax Area Code", FitText(TextValue, MaxStrLen(GenJournalLine."Tax Area Code")));
        if GetText(LineObject, 'taxGroupCode', TextValue) then
            GenJournalLine.Validate("Tax Group Code", FitText(TextValue, MaxStrLen(GenJournalLine."Tax Group Code")));
        if GetBoolean(LineObject, 'taxLiable', BoolValue) then
            GenJournalLine.Validate("Tax Liable", BoolValue);

        if GetDecimal(LineObject, 'amount', DecValue) then
            GenJournalLine.Validate(Amount, DecValue);
        // After Amount: RTRCurrencyFactorAPI is an addlast page extension field, so BC applies
        // it last today, recomputing the LCY amounts from the factor.
        if GetDecimal(LineObject, 'RTRCurrencyFactorAPI', DecValue) then
            GenJournalLine.Validate("Currency Factor", DecValue);

        if GetText(LineObject, 'comment', TextValue) then
            GenJournalLine.Comment := FitText(TextValue, MaxStrLen(GenJournalLine.Comment));
        if GetText(LineObject, 'sourceType', TextValue) then
            GenJournalLine.Validate("Source Type", ParseSourceType(TextValue, LineIndex));
        // Last of the account fields, as on page 6407: validating it overwrites Account No.
        // with the customer's number.
        if GetGuid(LineObject, 'customerId', GuidValue, LineIndex) then
            GenJournalLine.Validate("Customer Id", GuidValue);

        ApplyExtraFields(GenJournalLine, LineObject, LineIndex);

        // Last: every validate above recalculates the VAT amount BC computed for itself.
        if GetDecimal(LineObject, 'RTRVATAmountAPI', DecValue) then
            ApplyVatAmountOverride(GenJournalLine, DecValue);

        GenJournalLine.Insert(true);
    end;

    // Puts back what validating Account No. copied off the account (see GetGLAccount in
    // GenJournalLine.Table.al). Only called for id-identified accounts — see the call site.
    local procedure RestoreAccountDefaults(var GenJournalLine: Record "Gen. Journal Line"; SnapshotLine: Record "Gen. Journal Line"; LineObject: JsonObject)
    begin
        if not HasValue(LineObject, 'genPostingType') then
            GenJournalLine."Gen. Posting Type" := SnapshotLine."Gen. Posting Type";
        if not HasValue(LineObject, 'genBusPostingGroup') then
            GenJournalLine."Gen. Bus. Posting Group" := SnapshotLine."Gen. Bus. Posting Group";
        if not HasValue(LineObject, 'genProdPostingGroup') then
            GenJournalLine."Gen. Prod. Posting Group" := SnapshotLine."Gen. Prod. Posting Group";
        if not HasValue(LineObject, 'RTRVatBusPostingGroupAPI') and not HasValue(LineObject, 'vatBusPostingGroup') then
            GenJournalLine."VAT Bus. Posting Group" := SnapshotLine."VAT Bus. Posting Group";
        if not HasValue(LineObject, 'vatProdPostingGroup') and not HasValue(LineObject, 'RTRVatProdPostingGroupAPI') then
            GenJournalLine."VAT Prod. Posting Group" := SnapshotLine."VAT Prod. Posting Group";
        if not HasValue(LineObject, 'taxAreaCode') then
            GenJournalLine."Tax Area Code" := SnapshotLine."Tax Area Code";
        if not HasValue(LineObject, 'taxLiable') then
            GenJournalLine."Tax Liable" := SnapshotLine."Tax Liable";
        if not HasValue(LineObject, 'taxGroupCode') then
            GenJournalLine."Tax Group Code" := SnapshotLine."Tax Group Code";
        if not HasValue(LineObject, 'deferralCode') then
            GenJournalLine."Deferral Code" := SnapshotLine."Deferral Code";
        // Set alongside the posting groups above; without it a US-localized account leaves the
        // line on Sales Tax where the OData path leaves it on Normal Tax.
        if not HasValue(LineObject, 'vatCalculationType') then
            GenJournalLine."VAT Calculation Type" := SnapshotLine."VAT Calculation Type";
        // Account No. validate ends with Validate("VAT Prod. Posting Group"), which sets
        // "VAT %" and then recomputes VAT Amount / VAT Base Amount from it. Restoring the
        // group alone would leave the line calculating VAT at the account's rate.
        if not HasValue(LineObject, 'vatPercent') then begin
            GenJournalLine."VAT %" := SnapshotLine."VAT %";
            GenJournalLine."VAT Amount" := SnapshotLine."VAT Amount";
            GenJournalLine."VAT Base Amount" := SnapshotLine."VAT Base Amount";
        end;
        // ...and with CreateDimFromDefaultDim, which applies the account's default dimensions.
        if not HasValue(LineObject, 'dimensionSetId') then
            GenJournalLine."Dimension Set ID" := SnapshotLine."Dimension Set ID";
        if not HasValue(LineObject, 'shortcutDimension1Code') then
            GenJournalLine."Shortcut Dimension 1 Code" := SnapshotLine."Shortcut Dimension 1 Code";
        if not HasValue(LineObject, 'shortcutDimension2Code') then
            GenJournalLine."Shortcut Dimension 2 Code" := SnapshotLine."Shortcut Dimension 2 Code";
        // GetGLAccount takes Currency Code from the account's Source Currency Code. Left in
        // place it converts the line: a 700 line against an AED account posted 163.63 to the
        // ledger. Amount is validated later, so restoring the factor here is enough for the
        // LCY amounts to come out right.
        if not HasValue(LineObject, 'currencyCode') then begin
            GenJournalLine."Currency Code" := SnapshotLine."Currency Code";
            GenJournalLine."Currency Factor" := SnapshotLine."Currency Factor";
        end;
    end;

    local procedure RebuildDimensionsFromBalAccount(var GenJournalLine: Record "Gen. Journal Line")
    var
        AccountNo: Code[20];
    begin
        AccountNo := GenJournalLine."Account No.";
        GenJournalLine."Account No." := '';
        GenJournalLine.CreateDimFromDefaultDim(GenJournalLine.FieldNo("Bal. Account No."));
        GenJournalLine."Account No." := AccountNo;
    end;

    // OData rejects a value longer than the field; cutting it could land on a different code that exists.
    local procedure FitText(Value: Text; MaxLength: Integer): Text
    begin
        if StrLen(Value) > MaxLength then
            Error('Line %1: "%2" is %3 characters, but the field allows at most %4.', CurrentLineIndex, Value, StrLen(Value), MaxLength);
        exit(Value);
    end;

    local procedure HasValue(LineObject: JsonObject; FieldKey: Text): Boolean
    var
        ValueToken: JsonToken;
    begin
        exit(GetValueToken(LineObject, FieldKey, ValueToken));
    end;

    // Anything the explicit list above doesn't cover is applied by name, limited to the fields
    // page 6407 exposes, page extensions included. FieldRef.Validate runs the table field's
    // OnValidate; a trigger on a page-extension control does not run (AL can't drive the page).
    local procedure ApplyExtraFields(var GenJournalLine: Record "Gen. Journal Line"; LineObject: JsonObject; LineIndex: Integer)
    var
        RecRef: RecordRef;
        FieldKeys: List of [Text];
        FieldKey: Text;
        ValueToken: JsonToken;
        Applied: Boolean;
    begin
        RecRef.GetTable(GenJournalLine);
        FieldKeys := LineObject.Keys();

        foreach FieldKey in FieldKeys do begin
            if not IsHandledKey(FieldKey) then begin
                LineObject.Get(FieldKey, ValueToken);
                ApplyExtraField(RecRef, FieldKey, ValueToken, LineIndex);
                Applied := true;
            end;
        end;

        if Applied then
            RecRef.SetTable(GenJournalLine);
    end;

    local procedure ApplyExtraField(var RecRef: RecordRef; FieldKey: Text; ValueToken: JsonToken; LineIndex: Integer)
    var
        PageControlField: Record "Page Control Field";
        FldRef: FieldRef;
        Canonical: Text;
    begin
        if not ValueToken.IsValue() then
            Error('Line %1: field "%2" is not supported by this endpoint.', LineIndex, FieldKey);

        // The ordered path reads its keys by exact spelling. A key that only resembles one of
        // them would otherwise be silently dropped — creating a line with no account, or no
        // tax override — so say which spelling to use instead.
        Canonical := CanonicalHandledKey(FieldKey);
        if Canonical <> '' then
            Error('Line %1: "%2" is not read. Use "%3".', LineIndex, FieldKey, Canonical);

        // Validating Journal Batch Id would move the line out of the bound batch; the id is BC's to assign.
        if (NormalizeFieldName(FieldKey) = 'JOURNALBATCHID') or (NormalizeFieldName(FieldKey) = 'ID') then
            Error('Line %1: field "%2" cannot be set; lines are created in the batch the action is called on.', LineIndex, FieldKey);

        // Same fields the OData page accepts, including page extensions installed on this tenant.
        if not FindPageControl(FieldKey, PageControlField) then
            Error('Line %1: field "%2" is not exposed by workflowGenJournalLines.', LineIndex, FieldKey);

        if (PageControlField.FieldNo = 0) or (PageControlField.TableNo <> Database::"Gen. Journal Line") then
            Error('Line %1: field "%2" is a page field with no journal line field behind it, so createLines cannot set it.', LineIndex, FieldKey);

        FldRef := RecRef.Field(PageControlField.FieldNo);
        SetFieldFromJson(FldRef, ValueToken, FieldKey, LineIndex);
    end;

    local procedure FindPageControl(FieldKey: Text; var PageControlField: Record "Page Control Field"): Boolean
    begin
        PageControlField.SetRange(PageNo, Page::"Gen. Journal Line Entity");
        if PageControlField.FindSet() then
            repeat
                if NormalizeFieldName(PageControlField.ControlName) = NormalizeFieldName(FieldKey) then
                    exit(true);
            until PageControlField.Next() = 0;

        exit(false);
    end;

    local procedure SetFieldFromJson(var FldRef: FieldRef; ValueToken: JsonToken; FieldKey: Text; LineIndex: Integer)
    var
        TextValue: Text;
        DateValue: Date;
        GuidValue: Guid;
        DateFormulaValue: DateFormula;
    begin
        if ValueToken.AsValue().IsNull() then
            exit;

        case FldRef.Type of
            FieldType::Text, FieldType::Code:
                FldRef.Validate(FitText(ValueToken.AsValue().AsText(), FldRef.Length));
            FieldType::Integer:
                FldRef.Validate(ValueToken.AsValue().AsInteger());
            FieldType::BigInteger:
                FldRef.Validate(ValueToken.AsValue().AsBigInteger());
            FieldType::Decimal:
                FldRef.Validate(ValueToken.AsValue().AsDecimal());
            FieldType::Boolean:
                FldRef.Validate(ValueToken.AsValue().AsBoolean());
            FieldType::Date:
                begin
                    TextValue := ValueToken.AsValue().AsText();
                    if not Evaluate(DateValue, TextValue, 9) then
                        Error('Line %1: "%2" is not a valid date for field "%3".', LineIndex, TextValue, FieldKey);
                    FldRef.Validate(DateValue);
                end;
            FieldType::DateTime:
                FldRef.Validate(ValueToken.AsValue().AsDateTime());
            FieldType::Guid:
                begin
                    TextValue := ValueToken.AsValue().AsText();
                    if not Evaluate(GuidValue, TextValue) then
                        Error('Line %1: "%2" is not a valid id for field "%3".', LineIndex, TextValue, FieldKey);
                    FldRef.Validate(GuidValue);
                end;
            FieldType::Option:
                SetOptionField(FldRef, ValueToken.AsValue().AsText(), FieldKey, LineIndex);
            FieldType::DateFormula:
                begin
                    TextValue := ValueToken.AsValue().AsText();
                    // Both spellings OData takes: the user's "1M" and the XML "<1M>".
                    if not Evaluate(DateFormulaValue, TextValue) then
                        if not Evaluate(DateFormulaValue, TextValue, 9) then
                            Error('Line %1: "%2" is not a valid date formula for field "%3".', LineIndex, TextValue, FieldKey);
                    FldRef.Validate(DateFormulaValue);
                end;
            else
                Error('Line %1: field "%2" has a type this endpoint cannot set.', LineIndex, FieldKey);
        end;
    end;

    // Empty unless the key resembles a handled one, in which case the exact spelling to use.
    local procedure CanonicalHandledKey(FieldKey: Text): Text
    var
        HandledKeys: List of [Text];
        Handled: Text;
    begin
        HandledKeys := HandledKeyList();
        foreach Handled in HandledKeys do
            if NormalizeFieldName(Handled) = NormalizeFieldName(FieldKey) then
                exit(Handled);

        exit('');
    end;

    local procedure NormalizeFieldName(Value: Text) Normalized: Text
    var
        Builder: TextBuilder;
        Allowed: Text;
        Character: Char;
        i: Integer;
    begin
        Allowed := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        Value := UpperCase(Value);
        Value := Value.Replace('%', 'PERCENT');

        for i := 1 to StrLen(Value) do begin
            Character := Value[i];
            if StrPos(Allowed, Format(Character)) > 0 then
                Builder.Append(Character);
        end;

        Normalized := Builder.ToText();
        exit(Normalized.Replace('NUMBER', 'NO'));
    end;

    // Setting an option/enum field through a FieldRef is where the ordinal trap lives: for an
    // enum, position in OptionMembers is not the ordinal once the enum has gaps (Gen. Journal
    // Account Type jumps 6 -> 10) or a localization adds values at 50000+. Let BC resolve the
    // name itself; the positional lookup is only for a value it cannot resolve as a name.
    local procedure SetOptionField(var FldRef: FieldRef; Value: Text; FieldKey: Text; LineIndex: Integer)
    var
        Members: List of [Text];
        MemberList: Text;
        Member: Text;
        i: Integer;
    begin
        MemberList := FldRef.OptionMembers;
        Members := MemberList.Split(',');
        foreach Member in Members do
            if UpperCase(Member.Trim()) = UpperCase(Value.Trim()) then begin
                // Outside a TryFunction, so a real validation error surfaces instead of falling back.
                FldRef.Validate(Member.Trim());
                exit;
            end;

        Error('Line %1: "%2" is not a valid value for field "%3". Valid values: %4.', LineIndex, Value, FieldKey, MemberList);
    end;

    // The exact spelling of a key the ordered path consumes. A near miss is rejected rather
    // than passed through — see CanonicalHandledKey.
    local procedure IsHandledKey(FieldKey: Text): Boolean
    var
        HandledKeys: List of [Text];
    begin
        HandledKeys := HandledKeyList();
        exit(HandledKeys.Contains(FieldKey));
    end;

    local procedure HandledKeyList() HandledKeys: List of [Text]
    begin
        // journalTemplateName / journalBatchName are taken from the batch the action is bound to.
        HandledKeys.Add('journalTemplateName');
        HandledKeys.Add('journalBatchName');
        HandledKeys.Add('lineNumber');
        HandledKeys.Add('postingDate');
        HandledKeys.Add('documentNumber');
        HandledKeys.Add('externalDocumentNumber');
        HandledKeys.Add('accountType');
        HandledKeys.Add('accountNumber');
        HandledKeys.Add('accountId');
        HandledKeys.Add('balAccountType');
        HandledKeys.Add('balAccountNumber');
        HandledKeys.Add('balancingAccountId');
        HandledKeys.Add('currencyCode');
        HandledKeys.Add('RTRCurrencyFactorAPI');
        HandledKeys.Add('genPostingType');
        HandledKeys.Add('genBusPostingGroup');
        HandledKeys.Add('genProdPostingGroup');
        HandledKeys.Add('vatBusPostingGroup');
        HandledKeys.Add('vatProdPostingGroup');
        HandledKeys.Add('RTRVatBusPostingGroupAPI');
        HandledKeys.Add('RTRVatProdPostingGroupAPI');
        HandledKeys.Add('balGenPostingType');
        HandledKeys.Add('balGenBusPostingGroup');
        HandledKeys.Add('balGenProdPostingGroup');
        HandledKeys.Add('balVatBusPostingGroup');
        HandledKeys.Add('balVatProdPostingGroup');
        HandledKeys.Add('taxAreaCode');
        HandledKeys.Add('taxGroupCode');
        HandledKeys.Add('taxLiable');
        HandledKeys.Add('amount');
        HandledKeys.Add('description');
        HandledKeys.Add('comment');
        HandledKeys.Add('sourceType');
        HandledKeys.Add('customerId');
        HandledKeys.Add('RTRVATAmountAPI');
    end;

    // Account number wins; an id is resolved to one so both take the same validated path.
    local procedure ResolveAccountNo(LineObject: JsonObject; NumberKey: Text; IdKey: Text; AccountType: Enum "Gen. Journal Account Type"; LineIndex: Integer) AccountNo: Text
    var
        GLAccount: Record "G/L Account";
        BankAccount: Record "Bank Account";
        Customer: Record Customer;
        Vendor: Record Vendor;
        AccountId: Guid;
        IdText: Text;
    begin
        if GetText(LineObject, NumberKey, AccountNo) then
            exit(AccountNo);

        if not GetText(LineObject, IdKey, IdText) then
            exit('');

        if not Evaluate(AccountId, IdText) then
            Error('Line %1: "%2" is not a valid id for "%3".', LineIndex, IdText, IdKey);

        case AccountType of
            AccountType::"G/L Account":
                if GLAccount.GetBySystemId(AccountId) then
                    exit(GLAccount."No.");
            AccountType::"Bank Account":
                if BankAccount.GetBySystemId(AccountId) then
                    exit(BankAccount."No.");
            AccountType::Customer:
                if Customer.GetBySystemId(AccountId) then
                    exit(Customer."No.");
            AccountType::Vendor:
                if Vendor.GetBySystemId(AccountId) then
                    exit(Vendor."No.");
            else
                Error('Line %1: "%2" cannot be resolved for account type %3 — send a number instead.', LineIndex, IdKey, AccountType);
        end;

        Error('Line %1: no %2 found with id %3.', LineIndex, AccountType, IdText);
    end;

    local procedure ParseAccountType(Value: Text; FieldKey: Text; LineIndex: Integer) AccountType: Enum "Gen. Journal Account Type"
    var
        Names: List of [Text];
        Ordinals: List of [Integer];
        i: Integer;
    begin
        // Callers send the enum name, but not always in BC's casing ("G/L account").
        Names := Enum::"Gen. Journal Account Type".Names();
        Ordinals := Enum::"Gen. Journal Account Type".Ordinals();

        for i := 1 to Names.Count do
            if UpperCase(Names.Get(i)) = UpperCase(Value) then
                exit(Enum::"Gen. Journal Account Type".FromInteger(Ordinals.Get(i)));

        Error('Line %1: "%2" is not a valid %3.', LineIndex, Value, FieldKey);
    end;

    local procedure ParseGenPostingType(Value: Text; FieldKey: Text; LineIndex: Integer) GenPostingType: Enum "General Posting Type"
    var
        Names: List of [Text];
        Ordinals: List of [Integer];
        i: Integer;
    begin
        Names := Enum::"General Posting Type".Names();
        Ordinals := Enum::"General Posting Type".Ordinals();

        for i := 1 to Names.Count do
            if UpperCase(Names.Get(i)) = UpperCase(Value) then
                exit(Enum::"General Posting Type".FromInteger(Ordinals.Get(i)));

        Error('Line %1: "%2" is not a valid %3.', LineIndex, Value, FieldKey);
    end;

    local procedure ParseSourceType(Value: Text; LineIndex: Integer) SourceType: Enum "Gen. Journal Source Type"
    var
        Names: List of [Text];
        Ordinals: List of [Integer];
        i: Integer;
    begin
        Names := Enum::"Gen. Journal Source Type".Names();
        Ordinals := Enum::"Gen. Journal Source Type".Ordinals();

        for i := 1 to Names.Count do
            if UpperCase(Names.Get(i)) = UpperCase(Value) then
                exit(Enum::"Gen. Journal Source Type".FromInteger(Ordinals.Get(i)));

        Error('Line %1: "%2" is not a valid sourceType.', LineIndex, Value);
    end;

    local procedure AnyLineHasTaxOverride(LinesArray: JsonArray): Boolean
    var
        LineObject: JsonObject;
        LineToken: JsonToken;
        ValueToken: JsonToken;
    begin
        foreach LineToken in LinesArray do begin
            LineObject := LineToken.AsObject();
            if LineObject.Get('RTRVATAmountAPI', ValueToken) then
                if not ValueToken.AsValue().IsNull() then
                    exit(true);
        end;

        exit(false);
    end;

    // Same effect the backend gets today by PATCHing genJournalSetups before creating lines,
    // except it is part of this transaction, so a failed call leaves the tenant's setup alone.
    local procedure EnableVatDifference(JournalTemplateName: Code[10])
    var
        GenJnlTemplate: Record "Gen. Journal Template";
        GLSetup: Record "General Ledger Setup";
    begin
        if not GenJnlTemplate.Get(JournalTemplateName) then
            Error('Could not find journal template %1.', JournalTemplateName);

        if not GenJnlTemplate."Allow VAT Difference" then begin
            GenJnlTemplate."Allow VAT Difference" := true;
            GenJnlTemplate.Modify();
        end;

        GLSetup.Get();
        if GLSetup."Max. VAT Difference Allowed" = 0 then begin
            GLSetup."Max. VAT Difference Allowed" := 1000000000;
            GLSetup.Modify();
        end;
    end;

    local procedure NextLineNo(JournalTemplateName: Code[10]; JournalBatchName: Code[10]): Integer
    var
        GenJournalLine: Record "Gen. Journal Line";
    begin
        GenJournalLine.Reset();
        GenJournalLine.SetRange("Journal Template Name", JournalTemplateName);
        GenJournalLine.SetRange("Journal Batch Name", JournalBatchName);
        if GenJournalLine.FindLast() then
            exit(GenJournalLine."Line No." + 10000);

        exit(10000);
    end;

    local procedure GetText(LineObject: JsonObject; FieldKey: Text; var Value: Text): Boolean
    var
        ValueToken: JsonToken;
    begin
        Value := '';
        if not GetValueToken(LineObject, FieldKey, ValueToken) then
            exit(false);

        Value := ValueToken.AsValue().AsText();
        exit(true);
    end;

    local procedure GetDecimal(LineObject: JsonObject; FieldKey: Text; var Value: Decimal): Boolean
    var
        ValueToken: JsonToken;
    begin
        Value := 0;
        if not GetValueToken(LineObject, FieldKey, ValueToken) then
            exit(false);

        Value := ValueToken.AsValue().AsDecimal();
        exit(true);
    end;

    local procedure GetInt(LineObject: JsonObject; FieldKey: Text; var Value: Integer): Boolean
    var
        ValueToken: JsonToken;
    begin
        Value := 0;
        if not GetValueToken(LineObject, FieldKey, ValueToken) then
            exit(false);

        Value := ValueToken.AsValue().AsInteger();
        exit(true);
    end;

    local procedure GetBoolean(LineObject: JsonObject; FieldKey: Text; var Value: Boolean): Boolean
    var
        ValueToken: JsonToken;
    begin
        Value := false;
        if not GetValueToken(LineObject, FieldKey, ValueToken) then
            exit(false);

        Value := ValueToken.AsValue().AsBoolean();
        exit(true);
    end;

    local procedure GetDate(LineObject: JsonObject; FieldKey: Text; var Value: Date; LineIndex: Integer): Boolean
    var
        ValueToken: JsonToken;
        TextValue: Text;
    begin
        Clear(Value);
        if not GetValueToken(LineObject, FieldKey, ValueToken) then
            exit(false);

        TextValue := ValueToken.AsValue().AsText();
        if not Evaluate(Value, TextValue, 9) then
            Error('Line %1: "%2" is not a valid date for "%3".', LineIndex, TextValue, FieldKey);

        exit(true);
    end;

    local procedure GetGuid(LineObject: JsonObject; FieldKey: Text; var Value: Guid; LineIndex: Integer): Boolean
    var
        ValueToken: JsonToken;
        TextValue: Text;
    begin
        Clear(Value);
        if not GetValueToken(LineObject, FieldKey, ValueToken) then
            exit(false);

        TextValue := ValueToken.AsValue().AsText();
        if not Evaluate(Value, TextValue) then
            Error('Line %1: "%2" is not a valid id for "%3".', LineIndex, TextValue, FieldKey);

        exit(true);
    end;

    // A null is the caller leaving the field alone, same as omitting it.
    local procedure GetValueToken(LineObject: JsonObject; FieldKey: Text; var ValueToken: JsonToken): Boolean
    begin
        if not LineObject.Get(FieldKey, ValueToken) then
            exit(false);

        if not ValueToken.IsValue() then
            Error('Line %1: field "%2" must be a plain value.', CurrentLineIndex, FieldKey);

        exit(not ValueToken.AsValue().IsNull());
    end;
}
