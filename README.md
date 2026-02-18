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

1. Test in sandbox first
2. Not done yet, WIP

## Resources

- [AL Language Docs](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-dev-overview)
- [BC API Reference](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/api-reference/v2.0/)
