# CI/CD Authentication Guide

This guide explains how to set up authentication for the BACPAC to Container toolkit in various CI/CD environments.

## Overview

The toolkit supports multiple authentication methods:

1. **Azure AD with Access Token** (Recommended for CI/CD)
2. **Azure AD Interactive** (Development only)
3. **SQL Authentication** (Fallback option)

## Azure DevOps Pipelines

### Method 1: Azure CLI Task (Recommended)

```yaml
steps:
- task: AzureCLI@2
  displayName: 'Export Database and Build Container'
  inputs:
    azureSubscription: '$(serviceConnection)'  # Your service connection
    scriptType: 'pscore'
    scriptLocation: 'scriptPath'
    scriptPath: 'build.ps1'
    arguments: |
      -SubscriptionId $(AZURE_SUBSCRIPTION_ID)
      -ResourceGroupName $(RESOURCE_GROUP_NAME)
      -ServerName $(SQL_SERVER_NAME)
      -DatabaseName $(DATABASE_NAME)
      -StorageAccountName $(STORAGE_ACCOUNT_NAME)
      -ContainerName "bacpacs"
      -BacpacFileName "$(Build.BuildId).bacpac"
      -ImageName $(IMAGE_NAME)
      -ImageTag $(Build.BuildNumber)
      -RegistryName $(REGISTRY_NAME)
      -LogLevel "Info"
```

### Method 2: Separate Authentication + PowerShell

```yaml
steps:
- task: AzureCLI@2
  displayName: 'Azure Login'
  inputs:
    azureSubscription: '$(serviceConnection)'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: 'echo "Azure CLI authenticated"'

- task: PowerShell@2
  displayName: 'Export and Build'
  inputs:
    targetType: 'filePath'
    filePath: 'build.ps1'
    arguments: |
      -SubscriptionId $(AZURE_SUBSCRIPTION_ID)
      -ResourceGroupName $(RESOURCE_GROUP_NAME)
      # ... other parameters
```

### Required Service Principal Permissions

Your Azure DevOps service connection needs:

**Azure SQL Database:**
- `SQL DB Contributor` or custom role with:
  - `Microsoft.Sql/servers/databases/read`
  - `Microsoft.Sql/servers/databases/export/action`

**Storage Account:**
- `Storage Blob Data Contributor` or:
  - `Microsoft.Storage/storageAccounts/blobServices/containers/read`
  - `Microsoft.Storage/storageAccounts/blobServices/containers/write`
  - `Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action`

**Container Registry:**
- `AcrPush` role for image publishing

## GitHub Actions

### Using azure/login Action

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Setup PowerShell
      uses: microsoft/setup-powershell@v1
    
    - name: Build Database Container
      shell: pwsh
      run: |
        .\build.ps1 `
          -SubscriptionId "${{ secrets.AZURE_SUBSCRIPTION_ID }}" `
          -ResourceGroupName "${{ secrets.RESOURCE_GROUP_NAME }}" `
          # ... other parameters
```

### Azure Credentials Secret Format

Create a service principal and store in `AZURE_CREDENTIALS` secret:

```json
{
  "clientId": "your-client-id",
  "clientSecret": "your-client-secret",
  "subscriptionId": "your-subscription-id",
  "tenantId": "your-tenant-id"
}
```

## Other CI/CD Platforms

### Jenkins with Azure CLI Plugin

```groovy
pipeline {
    agent any
    environment {
        AZURE_SUBSCRIPTION_ID = credentials('azure-subscription-id')
        // ... other environment variables
    }
    stages {
        stage('Azure Login') {
            steps {
                withCredentials([azureServicePrincipal('azure-service-principal')]) {
                    sh 'az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET -t $AZURE_TENANT_ID'
                }
            }
        }
        stage('Build') {
            steps {
                pwsh '''
                    .\build.ps1 `
                        -SubscriptionId $env:AZURE_SUBSCRIPTION_ID `
                        # ... other parameters
                '''
            }
        }
    }
}
```

### GitLab CI

```yaml
variables:
  AZURE_SUBSCRIPTION_ID: "${AZURE_SUBSCRIPTION_ID}"
  
before_script:
  - az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} -t ${AZURE_TENANT_ID}

build:
  stage: build
  script:
    - pwsh -c "./build.ps1 -SubscriptionId ${AZURE_SUBSCRIPTION_ID} ..."
```

## Authentication Detection

The script automatically detects CI/CD environments using these environment variables:

- `SYSTEM_TEAMPROJECTID` (Azure DevOps)
- `GITHUB_ACTIONS` (GitHub Actions)
- `CI` (Generic CI indicator)
- `BUILD_BUILDID` (Azure DevOps)

When detected, it:
1. Uses non-interactive authentication
2. Leverages existing Azure CLI tokens
3. Prevents authentication prompts
4. Provides clear error messages if authentication fails

## Troubleshooting

### "No valid Azure CLI authentication found"

**Cause**: The Azure CLI is not authenticated or the token has expired.

**Solutions**:
1. Ensure Azure CLI task/action runs before PowerShell scripts
2. Verify service principal has required permissions
3. Check service connection configuration

### "Authentication prompt appeared"

**Cause**: CI/CD environment not properly detected or no valid token.

**Solutions**:
1. Set `CI=true` environment variable explicitly
2. Use SQL authentication as fallback
3. Verify Azure CLI is installed and configured

### "Access denied to database"

**Cause**: Service principal lacks database permissions.

**Solutions**:
1. Grant appropriate SQL database roles
2. Add service principal as Azure AD admin on SQL Server
3. Use SQL authentication with proper credentials

### "SqlPackage authentication failed"

**Cause**: Token format or permissions issue.

**Solutions**:
1. Verify SqlPackage version supports /AccessToken parameter
2. Check that Azure AD authentication is enabled on SQL Server
3. Ensure firewall allows CI/CD agent IP addresses

## Security Best Practices

1. **Use Service Principals**: Never use personal accounts in CI/CD
2. **Least Privilege**: Grant only required permissions
3. **Rotate Secrets**: Regular rotation of service principal secrets
4. **Audit Access**: Monitor authentication and access logs
5. **Secure Variables**: Use CI/CD platform's secure variable features
6. **Network Security**: Restrict access using firewall rules and private endpoints

## Testing Authentication

You can test authentication in your CI/CD environment:

```powershell
# Test Azure CLI authentication
az account show

# Test database connectivity (replace with your values)
sqlpackage /Action:Export /TargetFile:test.bacpac /SourceConnectionString:"Data Source=your-server.database.windows.net;Initial Catalog=your-db;" /UniversalAuthentication:True
```

## Environment Variables Summary

| Variable | Purpose | Required |
|----------|---------|----------|
| `AZURE_SUBSCRIPTION_ID` | Target subscription | Yes |
| `AZURE_CLIENT_ID` | Service principal ID | Yes (if using SP) |
| `AZURE_CLIENT_SECRET` | Service principal secret | Yes (if using SP) |
| `AZURE_TENANT_ID` | Azure AD tenant | Yes (if using SP) |
| `CI` | Force non-interactive mode | Optional |
