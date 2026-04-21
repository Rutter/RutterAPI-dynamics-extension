#if PTE
page 71707 "RTR Purch. Order Actions API"
#else
page 71692589 "RTR Purch. Order Actions API"
#endif
{
    APIVersion = 'v2.0';
    EntityCaption = 'Purchase Order Action';
    EntitySetCaption = 'Purchase Order Actions';
    EntityName = 'purchaseOrderAction';
    EntitySetName = 'purchaseOrderActions';
    APIPublisher = 'Rutter';
    APIGroup = 'RutterAPI';
    PageType = API;
    SourceTable = "Purchase Header";
    SourceTableView = WHERE("Document Type" = CONST(Order));
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
                field(number; Rec."No.")
                {
                    Caption = 'Number';
                    Editable = false;
                }
                field(vendorNumber; Rec."Buy-from Vendor No.")
                {
                    Caption = 'Vendor Number';
                    Editable = false;
                }
                field(status; Rec.Status)
                {
                    Caption = 'Status';
                    Editable = false;
                }
            }
        }
    }

    // Receives and invoices the purchase order in one step.
    // BC standard posting pipeline:
    //   - Creates Purch. Rcpt. Header/Lines (receivedQuantity updated)
    //   - Creates Posted Purch. Invoice Header/Lines (invoicedQuantity updated)
    //   - Order No. natively linked on posted invoice
    //   - PO quantities properly consumed
    //
    // Call via:
    //   POST .../purchaseOrderActions({systemId})/Microsoft.NAV.postReceiveAndInvoice
    [ServiceEnabled]
    procedure postReceiveAndInvoice(var ActionContext: WebServiceActionContext)
    var
        PurchPost: Codeunit "Purch.-Post";
        OrderNo: Code[20];
    begin
        if Rec.Status = Rec.Status::Open then begin
            Rec.Validate(Status, Rec.Status::Released);
            Rec.Modify(true);
        end;

        OrderNo := Rec."No.";

        Rec.Receive := true;
        Rec.Invoice := true;
        PurchPost.Run(Rec);

        ActionContext.SetObjectType(ObjectType::Page);
        #if PTE
        ActionContext.SetObjectId(Page::"RTR Purch. Order Actions API");
        #else
        ActionContext.SetObjectId(Page::"RTR Purch. Order Actions API");
        #endif
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Get);
    end;
}
