# Required Permissions for BACPAC to Container Toolkit

This document outlines the specific permissions required for each component of the BACPAC to Container toolkit.

## Azure SQL Database Permissions

### For Database Export Operations

Your Azure AD account needs the following **database-level** permissions to export a database:

```sql
-- Replace 'your-email@domain.com' with your actual Azure AD email
CREATE USER [your-email@domain.com] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [your-email@domain.com];
ALTER ROLE db_datawriter ADD MEMBER [your-email@domain.com];
ALTER ROLE db_owner ADD MEMBER [your-email@domain.com]; -- Required for export operations
```

### How to Grant Permissions

1. **Connect to the target database** (not master) using SQL Server Management Studio, Azure Data Studio, or sqlcmd
2. **Run the above SQL commands** with your actual Azure AD email address
3. **Must be executed by**: A user with `db_owner` role or higher privileges

### Alternative: SQL Authentication

If Azure AD authentication is not available, you can use SQL authentication with the admin login credentials configured on the Azure SQL Server.

## Azure Blob Storage Permissions

### Required RBAC Role

Your Azure AD account needs one of the following roles on the **storage account** or **container**:

- **Storage Blob Data Contributor** (recommended)
- **Storage Blob Data Owner**

### Specific Permissions Required

If using custom roles, ensure these permissions are included:

```json
{
  "permissions": [
    {
      "actions": [],
      "notActions": [],
      "dataActions": [
        "Microsoft.Storage/storageAccounts/blobServices/containers/read",
        "Microsoft.Storage/storageAccounts/blobServices/containers/write",
        "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
        "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
        "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
        "Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action"
      ],
      "notDataActions": []
    }
  ]
}
```

### How to Grant Permissions

1. **Navigate to Azure Portal** → Storage Account → Access Control (IAM)
2. **Click "Add role assignment"**
3. **Select role**: "Storage Blob Data Contributor"
4. **Assign access to**: User, group, or service principal
5. **Select**: Your Azure AD account or service principal

## Azure Container Registry Permissions

### Required RBAC Role

For pushing container images, your Azure AD account needs:

- **AcrPush** role on the container registry

### Additional Roles (if needed)

- **Contributor**: If you need to create new repositories
- **AcrPull**: If you need to pull images (usually not required for this toolkit)

### How to Grant Permissions

1. **Navigate to Azure Portal** → Container Registry → Access Control (IAM)
2. **Click "Add role assignment"**
3. **Select role**: "AcrPush"
4. **Assign access to**: User, group, or service principal
5. **Select**: Your Azure AD account or service principal

## Service Principal Setup (for CI/CD)

### Creating a Service Principal

```bash
# Create service principal
az ad sp create-for-rbac --name "bacpac-container-toolkit" --role Contributor --scopes /subscriptions/{subscription-id}
```

### Required Role Assignments for Service Principal

```bash
# Storage permissions
az role assignment create \
  --assignee {service-principal-id} \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.Storage/storageAccounts/{storage-name}

# Container registry permissions
az role assignment create \
  --assignee {service-principal-id} \
  --role "AcrPush" \
  --scope /subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.ContainerRegistry/registries/{registry-name}

# SQL Server permissions (for server-level operations if needed)
az role assignment create \
  --assignee {service-principal-id} \
  --role "SQL Server Contributor" \
  --scope /subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.Sql/servers/{server-name}
```

### Database-Level Permissions for Service Principal

```sql
-- Connect to the target database and run:
CREATE USER [bacpac-container-toolkit] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER [bacpac-container-toolkit];
```

## Troubleshooting Permission Issues

### Common Error Messages

#### "Login failed for user"
- **Issue**: Database-level permissions not granted
- **Solution**: Ensure the Azure AD user is added to the database with appropriate roles

#### "Authorization permission mismatch"
- **Issue**: Storage account permissions missing
- **Solution**: Grant "Storage Blob Data Contributor" role

#### "unauthorized: authentication required"
- **Issue**: Container registry permissions missing  
- **Solution**: Grant "AcrPush" role on the registry

#### "Operation not allowed"
- **Issue**: SqlPackage export permissions insufficient
- **Solution**: Ensure `db_owner` role is granted for export operations

### Verification Commands

```powershell
# Test Azure authentication
az account show

# Test storage access
az storage blob list --account-name {storage-name} --container-name {container-name} --auth-mode login

# Test ACR access
az acr login --name {registry-name}

# Test SQL connection (requires sqlcmd with Azure AD auth)
sqlcmd -S {server-name}.database.windows.net -d {database-name} -G -Q "SELECT USER_NAME()"
```

## Best Practices

1. **Use Azure AD Authentication**: Preferred over SQL authentication for audit and security
2. **Principle of Least Privilege**: Grant only the minimum required permissions
3. **Service Principals for CI/CD**: Don't use personal accounts in automated pipelines
4. **Regular Access Review**: Periodically review and clean up unused permissions
5. **Separate Environments**: Use different service principals for dev/staging/production
6. **Monitor Access**: Enable audit logging for storage and database access

## Security Considerations

- **Never store credentials in code**: Use Azure Key Vault or CI/CD secret management
- **Rotate service principal secrets**: Set expiration dates and rotate regularly
- **Use managed identities when possible**: For Azure-hosted CI/CD systems
- **Enable audit logging**: Track all database and storage access
- **Implement conditional access**: Use Azure AD conditional access policies where appropriate
