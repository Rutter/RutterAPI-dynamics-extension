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
        codeunit "RTR Entry Application Mgt" = X,
        page "RTR Applied Cust. Entries API" = X,
        page "RTR Cust. Ledger Entries API" = X,
        page "RTR Bank Accounts API" = X,
        page "RTR Tax Areas API" = X;
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
        codeunit "RTR Entry Application Mgt" = X,
        page "RTR Applied Cust. Entries API" = X,
        page "RTR Cust. Ledger Entries API" = X,
        page "RTR Bank Accounts API" = X,
        page "RTR Tax Areas API" = X;
}
#endif