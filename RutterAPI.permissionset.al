#if PTE
permissionset 71692 "RTR Rutter API"
{
    Caption = 'Rutter API';
    Access = Public;
    Assignable = true;
    Permissions = page "RTR Applied Vendor Entries API" = X,
        page "RTR Vendor Ledger Entries API" = X,
        codeunit "RTR Rutter Management" = X,
        page "RTR Related G/L Entries API" = X,
        codeunit "RTR Entry Application Mgt" = X;
}
#else
permissionset 71692575 "RTR Rutter API"
{
    Caption = 'Rutter API';
    Access = Public;
    Assignable = true;
    Permissions = page "RTR Applied Vendor Entries API" = X,
        page "RTR Vendor Ledger Entries API" = X,
        codeunit "RTR Rutter Management" = X,
        page "RTR Related G/L Entries API" = X,
        codeunit "RTR Entry Application Mgt" = X;
}
#endif