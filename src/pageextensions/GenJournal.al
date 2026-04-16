#if PTE
pageextension 71707 "RTR General Journal" extends "General Journal"
#else
pageextension 71692590 "RTR General Journal" extends "General Journal"
#endif
{
    layout
    {
        addafter(Amount)
        {
            field(RTRVATAmount; Rec."VAT Amount")
            {
                Caption = 'Tax Amount';
                ApplicationArea = All;
            }
            field(RTRVATDifference; Rec."VAT Difference")
            {
                Caption = 'Tax Difference';
                ApplicationArea = All;
            }
        }
    }
}
