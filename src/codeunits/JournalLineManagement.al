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
            CreatedIds.Add(Format(GenJournalLine.SystemId, 0, 4));
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
            GenJournalLine.Validate("Document No.", CopyStr(TextValue, 1, MaxStrLen(GenJournalLine."Document No.")));
        if GetText(LineObject, 'externalDocumentNumber', TextValue) then
            GenJournalLine.Validate("External Document No.", CopyStr(TextValue, 1, MaxStrLen(GenJournalLine."External Document No.")));

        // Account type before account number, both validated, in the same transaction: this is
        // what removes the backend's two-step PATCH for bank accounts.
        if GetText(LineObject, 'accountType', TextValue) then
            GenJournalLine.Validate("Account Type", ParseAccountType(TextValue, 'accountType', LineIndex));
        TextValue := ResolveAccountNo(LineObject, 'accountNumber', 'accountId', GenJournalLine."Account Type", LineIndex);
        if TextValue <> '' then begin
            SnapshotLine := GenJournalLine;
            GenJournalLine.Validate("Account No.", CopyStr(TextValue, 1, MaxStrLen(GenJournalLine."Account No.")));
            RestoreAccountDefaults(GenJournalLine, SnapshotLine, LineObject);
        end;

        // After the account, never before: Due Date is derived here, and validating an account
        // afterwards clears it (page 6407 orders accountNumber then postingDate for the same reason).
        if GetDate(LineObject, 'postingDate', DateValue, LineIndex) then
            GenJournalLine.Validate("Posting Date", DateValue);

        // After the account (which overwrites it with the account name) but before the bal
        // account (which overwrites it again) — page 6407's own order, which callers depend on.
        if GetText(LineObject, 'description', TextValue) then
            GenJournalLine.Validate(Description, CopyStr(TextValue, 1, MaxStrLen(GenJournalLine.Description)));

        if GetText(LineObject, 'balAccountType', TextValue) then
            GenJournalLine.Validate("Bal. Account Type", ParseAccountType(TextValue, 'balAccountType', LineIndex));
        TextValue := ResolveAccountNo(LineObject, 'balAccountNumber', 'balancingAccountId', GenJournalLine."Bal. Account Type", LineIndex);
        if TextValue <> '' then
            GenJournalLine.Validate("Bal. Account No.", CopyStr(TextValue, 1, MaxStrLen(GenJournalLine."Bal. Account No.")));

        if GetText(LineObject, 'currencyCode', TextValue) then
            GenJournalLine.Validate("Currency Code", CopyStr(TextValue, 1, MaxStrLen(GenJournalLine."Currency Code")));

        // Gen. Posting Type first: the VAT posting groups read it to resolve the VAT setup.
        // This is the ordering the backend cannot express in one OData request, which is why
        // it PATCHes the posting groups separately today.
        if GetText(LineObject, 'genPostingType', TextValue) then
            GenJournalLine.Validate("Gen. Posting Type", ParseGenPostingType(TextValue, LineIndex));
        if GetText(LineObject, 'RTRVatBusPostingGroupAPI', TextValue) then
            GenJournalLine.Validate("VAT Bus. Posting Group", CopyStr(TextValue, 1, MaxStrLen(GenJournalLine."VAT Bus. Posting Group")));
        if GetText(LineObject, 'vatProdPostingGroup', TextValue) then
            GenJournalLine.Validate("VAT Prod. Posting Group", CopyStr(TextValue, 1, MaxStrLen(GenJournalLine."VAT Prod. Posting Group")));
        // The RTR override wins over vatProdPostingGroup: today it is applied in a later PATCH.
        if GetText(LineObject, 'RTRVatProdPostingGroupAPI', TextValue) then
            GenJournalLine.Validate("VAT Prod. Posting Group", CopyStr(TextValue, 1, MaxStrLen(GenJournalLine."VAT Prod. Posting Group")));

        if GetText(LineObject, 'taxAreaCode', TextValue) then
            GenJournalLine.Validate("Tax Area Code", CopyStr(TextValue, 1, MaxStrLen(GenJournalLine."Tax Area Code")));
        if GetText(LineObject, 'taxGroupCode', TextValue) then
            GenJournalLine.Validate("Tax Group Code", CopyStr(TextValue, 1, MaxStrLen(GenJournalLine."Tax Group Code")));
        if GetBoolean(LineObject, 'taxLiable', BoolValue) then
            GenJournalLine.Validate("Tax Liable", BoolValue);

        if GetDecimal(LineObject, 'amount', DecValue) then
            GenJournalLine.Validate(Amount, DecValue);
        // After Amount: RTRCurrencyFactorAPI is an addlast page extension field, so BC applies
        // it last today, recomputing the LCY amounts from the factor.
        if GetDecimal(LineObject, 'RTRCurrencyFactorAPI', DecValue) then
            GenJournalLine.Validate("Currency Factor", DecValue);

        if GetText(LineObject, 'comment', TextValue) then
            GenJournalLine.Comment := CopyStr(TextValue, 1, MaxStrLen(GenJournalLine.Comment));
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

    // Validating Account No. copies the account's posting and tax defaults onto the line (see
    // GetGLAccount in GenJournalLine.Table.al). The OData path sets Account No. through
    // "Account Id", a raw assign that skips all of it, so put back anything the caller did not
    // ask for — a line must not silently inherit a tax treatment nobody sent.
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
    end;

    local procedure HasValue(LineObject: JsonObject; FieldKey: Text): Boolean
    var
        ValueToken: JsonToken;
    begin
        exit(GetValueToken(LineObject, FieldKey, ValueToken));
    end;

    // Anything the explicit list above doesn't cover is applied by name against the table's own
    // fields, so callers keep the open-ended field access page 6407 gives them. Page 6407 is a
    // plain field-binding page with no triggers of its own, so a FieldRef.Validate matches it.
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
        FldRef: FieldRef;
        TargetName: Text;
        i: Integer;
    begin
        if not ValueToken.IsValue() then
            Error('Line %1: field "%2" is not supported by this endpoint.', LineIndex, FieldKey);

        TargetName := NormalizeFieldName(FieldKey);

        for i := 1 to RecRef.FieldCount do begin
            FldRef := RecRef.FieldIndex(i);
            if NormalizeFieldName(FldRef.Name) = TargetName then begin
                SetFieldFromJson(FldRef, ValueToken, FieldKey, LineIndex);
                exit;
            end;
        end;

        Error('Line %1: unknown field "%2".', LineIndex, FieldKey);
    end;

    local procedure SetFieldFromJson(var FldRef: FieldRef; ValueToken: JsonToken; FieldKey: Text; LineIndex: Integer)
    var
        TextValue: Text;
        DateValue: Date;
        GuidValue: Guid;
    begin
        if ValueToken.AsValue().IsNull() then
            exit;

        case FldRef.Type of
            FieldType::Text, FieldType::Code:
                FldRef.Validate(CopyStr(ValueToken.AsValue().AsText(), 1, FldRef.Length));
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
                FldRef.Validate(OptionOrdinal(FldRef, ValueToken.AsValue().AsText(), FieldKey, LineIndex));
            else
                Error('Line %1: field "%2" has a type this endpoint cannot set.', LineIndex, FieldKey);
        end;
    end;

    // OData property names and BC field names differ in fixed ways ("Account No." is exposed as
    // accountNumber, "VAT %" as vatPercent), so both sides are folded to the same shape.
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

    local procedure OptionOrdinal(FldRef: FieldRef; Value: Text; FieldKey: Text; LineIndex: Integer): Integer
    var
        Members: List of [Text];
        MemberList: Text;
        Member: Text;
        i: Integer;
    begin
        MemberList := FldRef.OptionMembers;
        Members := MemberList.Split(',');
        for i := 1 to Members.Count do begin
            Member := Members.Get(i);
            if UpperCase(Member.Trim()) = UpperCase(Value.Trim()) then
                exit(i - 1);
        end;

        Error('Line %1: "%2" is not a valid value for field "%3". Valid values: %4.', LineIndex, Value, FieldKey, MemberList);
    end;

    local procedure IsHandledKey(FieldKey: Text): Boolean
    var
        HandledKeys: List of [Text];
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
        HandledKeys.Add('vatProdPostingGroup');
        HandledKeys.Add('RTRVatBusPostingGroupAPI');
        HandledKeys.Add('RTRVatProdPostingGroupAPI');
        HandledKeys.Add('taxAreaCode');
        HandledKeys.Add('taxGroupCode');
        HandledKeys.Add('taxLiable');
        HandledKeys.Add('amount');
        HandledKeys.Add('description');
        HandledKeys.Add('comment');
        HandledKeys.Add('sourceType');
        HandledKeys.Add('customerId');
        HandledKeys.Add('RTRVATAmountAPI');

        exit(HandledKeys.Contains(FieldKey));
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

    local procedure ParseGenPostingType(Value: Text; LineIndex: Integer) GenPostingType: Enum "General Posting Type"
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

        Error('Line %1: "%2" is not a valid genPostingType.', LineIndex, Value);
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
            Error('Field "%1" must be a plain value.', FieldKey);

        exit(not ValueToken.AsValue().IsNull());
    end;
}
