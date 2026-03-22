# Rutter AccountLink - Dynamics 365 Business Central Extension

A Business Central AL extension that exposes custom API endpoints for Rutter's integration with Dynamics 365 Business Central.

## What is this?

This extension adds custom API endpoints to Dynamics 365 Business Central that expose data not available through standard APIs or OData endpoints (which aren't enabled by default for customers).

**How it works:**
1. Write AL code (`.al` files) defining API pages
2. Compile to create an `.app` package
3. Upload the `.app` to a BC environment
4. Access custom endpoints via standard BC API URLs

## Project Structure

```
src/pages/          # API endpoint definitions (TaxAreas.API.al, etc.)
src/codeunits/      # Business logic
src/tableextensions/ # Extensions to BC tables
app.json            # Extension metadata & version number
RutterAPI.permissionset.al  # Permissions
*.app               # Compiled packages
```

## Versioning

⚠️ **Important:** BC caches uploaded versions. Once you upload `22.4.0.0`, you cannot upload a different `22.4.0.0` - you must increment the version.

## Testing Changes

### (Optional) Create a Sandbox
- Go to [BC Admin Center](https://businesscentral.dynamics.com/)
- **Environments** → **New** → Choose **Sandbox**
- Select "Empty" (faster) or copy from Production
- Wait ~5-10 minutes

### 1. Compile the Extension
- In VS Code: Press `F5` or `Ctrl+Shift+P` → "AL: Publish"
- Generates `.app` file in project directory

### 2. Upload to Test Environment
- Open environment in browser
- Search for "Extension Management"
- **Upload Extension** → Select your `.app` file → **Install**

**NOTES**: Might need to delete the marketplace downloaded version (the deployed one) to avoid errors, and also the version has to be bumped everytime the extension is successfully installed (e.g xx.x.x.1 to xx.x.x.2). Two different versions can't co-exist, so every time you upload the extension the version number has to be bumped up.

### 3. Test with Postman

Get company ID:
```
GET https://api.businesscentral.dynamics.com/v2.0/<environment-name>/api/v2.0/companies
Auth: Bearer <oauth-token>
```

Test your endpoint:
```
GET https://api.businesscentral.dynamics.com/v2.0/<environment-name>/api/Rutter/RutterAPI/v2.0/companies(<company-id>)/<entitySetName>
Auth: Bearer <oauth-token>
```

### 4. Important notes

Most errors should come up during development via the vscode extension or our .vscode folder content. However, some errors could only come up when deploying to Partner Center. Last time we found some, they were related to some fields only available in the Dynamics US version. There is a way to locally run the validation that Partner Center runs, with a BC docker container, but it needs to be on Windows and it looks like it's not just pulling and starting the container, it needs a license. For this reason, testing locally does have some limitations.

However there is a (not totally reliable, but better than nothing) way to test these errors. Make a request to the UK company (from the dev account) and if there is an error somewhere, you'll get:
```
{              
    "error": {                                                                                                                                                                       
        "code": "Unknown",
        "message": "You cannot sign in to the company because your license has expired or the trial period has ended. However, you can still use the demonstration company.           
        CorrelationId:  74c3b4dd-2999-491f-970c-952a4cce3410."                                                                                                                               
    }                 
} 
```

Not totally reliable, we'll need a bigger sample to see if it's correct but so far we forced the error found while deploying `/taxAreas` and got this. With the deployed version, the endpoint would just return an empty array. Could be useful going forward.


### (Optional) Delete Sandbox When Done
- Admin Center → Environments → Delete

## Adding New Endpoints

1. Create new API page in `src/pages/YourEndpoint.API.al`
2. Add page permissions to `RutterAPI.permissionset.al`
3. Bump version in `app.json`
4. Compile and test in sandbox

**Key:** Field names in your AL code become JSON property names. Match existing OData formats to minimize backend changes.

## Common Issues

**"Different .app with same version" error**
- Solution: Increment version in `app.json`

**"Field name appears in multiple apps" error**
- Solution: Another version is installed. Uninstall it first (sandbox only!)

**API returns 404**
- Check extension is installed (Extension Management)
- Verify URL format and entity name

## Authentication

OAuth tokens are tenant-scoped, so the access token you get when calling the platform setup endpoint works for sandboxes too.

## Deploying to Production

1. Testing on Dynamics (first sandbox to be sure, then Production)
2. Create PR and merge
3. Sign the latest `.app` file version (see [Signing the .app Package](#signing-the-app-package) below)
4. Upload to Microsoft Partner Center (reach out to Eric for this step)
5. If there are no errors, it takes at least 3 days for the new version to be published

## Signing the .app Package

The `.app` file must be code-signed before uploading to Microsoft Partner Center. We use [jsign](https://ebourg.github.io/jsign/) with Azure Trusted Signing.

### Prerequisites

- **jsign** installed (`brew install jsign`)
- **Azure CLI** installed and logged in (`az login`)
- Access to the `Azure Signing Certificate` subscription under `rutterapi.com`

### Sign the package

1. Make sure you're logged into Azure CLI:
   ```bash
   az login
   ```

2. Sign the `.app` file:
   ```bash
   jsign --storetype TRUSTEDSIGNING \
     --keystore "https://eus.codesigning.azure.net" \
     --storepass "$(az account get-access-token --resource https://codesigning.azure.net --query accessToken -o tsv)" \
     --alias "RutterSigning/DynamicsCertificate" \
     Rutter_AccountLink_22.3.0.3.app
   ```
   Replace the `.app` filename with the current version.

3. You should see: `Adding Authenticode signature to <filename>`

### Troubleshooting

- **Token errors**: Make sure you're on the correct subscription (`az account set --subscription "Azure Signing Certificate"`)
- **Access denied**: You need the "Code Signing Certificate Profile Signer" role on the `RutterSigning` account in the `azure_signing` resource group

## Resources

- [AL Language Docs](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-dev-overview)
- [BC API Reference](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/)
