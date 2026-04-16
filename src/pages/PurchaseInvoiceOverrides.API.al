#if PTE
page 71707 "RTR Purch. Inv. Overrides API"
#else
page 71692589 "RTR Purch. Inv. Overrides API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Purchase Invoice Override';
    EntitySetCaption = 'Purchase Invoice Overrides';
    EntityName = 'purchaseInvoiceOverride';
    EntitySetName = 'purchaseInvoiceOverrides';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Purch. Inv. Entity Aggregate";
    ODataKeyFields = Id;
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
                field(id; Rec.Id)
                {
                    Caption = 'Id';
                    Editable = false;
                }
                field(number; Rec."No.")
                {
                    Caption = 'Number';
                    Editable = false;
                }
                // Write the PO number to link this purchase invoice to a purchase order.
                // The standard v2.0 API exposes orderId/orderNumber as read-only;
                // this field lets callers set "Order No." on the aggregate table.
                // The Purch. Inv. Aggregator codeunit syncs this back to the
                // underlying Purchase Header / Purch. Inv. Header.
                field(RTROrderNoAPI; Rec."Order No.")
                {
                    Caption = 'Order No. API';

                    trigger OnValidate()
                    var
                        PurchHeader: Record "Purchase Header";
                    begin
                        if Rec."Order No." <> '' then begin
                            // Validate that the referenced PO actually exists
                            PurchHeader.SetRange("Document Type", PurchHeader."Document Type"::Order);
                            PurchHeader.SetRange("No.", Rec."Order No.");
                            if not PurchHeader.FindFirst() then
                                Error('Purchase Order %1 does not exist.', Rec."Order No.");

                            // Validate same vendor
                            if PurchHeader."Buy-from Vendor No." <> Rec."Buy-from Vendor No." then
                                Error(
                                    'Purchase Order %1 belongs to vendor %2, but this invoice belongs to vendor %3.',
                                    Rec."Order No.",
                                    PurchHeader."Buy-from Vendor No.",
                                    Rec."Buy-from Vendor No."
                                );
                        end;
                    end;
                }
            }
        }
    }
}
