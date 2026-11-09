#if PTE
codeunit 71695 "RTR Suppress Apply Commit"
#else
codeunit 71692578 "RTR Suppress Apply Commit"
#endif
{
    // Bound only around PostPaymentAndApplyToBills' Apply() call, so nothing else is affected.
    EventSubscriberInstance = Manual;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"VendEntry-Apply Posted Entries", 'OnVendPostApplyVendLedgEntryOnBeforeCommit', '', false, false)]
    local procedure OnBeforeApplyCommit(var VendLedgerEntry: Record "Vendor Ledger Entry"; var SuppressCommit: Boolean)
    begin
        SuppressCommit := true;
    end;

    // PmtTolVend commits before applying, which would keep the posted payment if the apply fails.
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"VendEntry-Apply Posted Entries", 'OnApplyOnBeforePmtTolVend', '', false, false)]
    local procedure OnBeforePmtTolVend(VendLedgEntry: Record "Vendor Ledger Entry"; var PaymentToleranceMgt: Codeunit "Payment Tolerance Management"; PreviewMode: Boolean; var IsHandled: Boolean)
    begin
        PaymentToleranceMgt.SetSuppressCommit(true);
    end;
}
