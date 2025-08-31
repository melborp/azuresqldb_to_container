# Usage Examples

This document provides examples of how to use the BACPAC to Container toolkit in various scenarios.

## Basic Usage

### 1. Complete Process (Export → Build → Push)

```powershell
.\build.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -ResourceGroupName "my-rg" `
    -ServerName "my-sql-server" `
    -DatabaseName "MyDatabase" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BacpacFileName "mydatabase-$(Get-Date -Format 'yyyyMMdd-HHmmss').bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -RegistryName "myregistry" `
    -MigrationScriptPaths @("C:\scripts\001-add-tables.sql", "C:\scripts\002-add-indexes.sql") `
    -UpgradeScriptPaths @("C:\scripts\upgrade-to-v2.sql") `
    -LogLevel "Info"
```

### 2. Build from Existing BACPAC

```powershell
.\build.ps1 `
    -BacpacPath "https://mystorageaccount.blob.core.windows.net/bacpacs/database.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -SkipExport `
    -SkipPush `
    -MigrationScriptPaths @(".\migrations\*.sql") `
    -LogLevel "Debug"
```

### 3. Export Only

```powershell
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -ResourceGroupName "my-rg" `
    -ServerName "my-sql-server" `
    -DatabaseName "MyDatabase" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BacpacFileName "mydatabase.bacpac"
```

## CI/CD Integration Examples

### Azure DevOps Pipeline

```yaml
# azure-pipelines.yml
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

variables:
  registryName: 'myregistry'
  imageName: 'my-app-db'
  imageTag: '$(Build.BuildNumber)'

steps:
- task: PowerShell@2
  displayName: 'Export Database and Build Container'
  inputs:
    targetType: 'filePath'
    filePath: 'build.ps1'
    arguments: |
      -SubscriptionId $(AZURE_SUBSCRIPTION_ID)
      -ResourceGroupName $(RESOURCE_GROUP_NAME)
      -ServerName $(SQL_SERVER_NAME)
      -DatabaseName $(DATABASE_NAME)
      -StorageAccountName $(STORAGE_ACCOUNT_NAME)
      -ContainerName "bacpacs"
      -BacpacFileName "$(Build.BuildId).bacpac"
      -ImageName $(imageName)
      -ImageTag $(imageTag)
      -RegistryName $(registryName)
      -MigrationScriptPaths $(MIGRATION_SCRIPTS)
      -UpgradeScriptPaths $(UPGRADE_SCRIPTS)
      -LogLevel "Info"
    workingDirectory: '$(Build.SourcesDirectory)'
  env:
    AZURE_SUBSCRIPTION_ID: $(azureSubscriptionId)
    RESOURCE_GROUP_NAME: $(resourceGroupName)
    SQL_SERVER_NAME: $(sqlServerName)
    DATABASE_NAME: $(databaseName)
    STORAGE_ACCOUNT_NAME: $(storageAccountName)
    MIGRATION_SCRIPTS: $(migrationScripts)
    UPGRADE_SCRIPTS: $(upgradeScripts)
```

### GitHub Actions

```yaml
# .github/workflows/build-db-container.yml
name: Build Database Container

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY_NAME: myregistry
  IMAGE_NAME: my-app-db

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup PowerShell
      uses: microsoft/setup-powershell@v1
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Build Database Container
      shell: pwsh
      run: |
        .\build.ps1 `
          -SubscriptionId "${{ secrets.AZURE_SUBSCRIPTION_ID }}" `
          -ResourceGroupName "${{ secrets.RESOURCE_GROUP_NAME }}" `
          -ServerName "${{ secrets.SQL_SERVER_NAME }}" `
          -DatabaseName "${{ secrets.DATABASE_NAME }}" `
          -StorageAccountName "${{ secrets.STORAGE_ACCOUNT_NAME }}" `
          -ContainerName "bacpacs" `
          -BacpacFileName "${{ github.run_number }}.bacpac" `
          -ImageName "${{ env.IMAGE_NAME }}" `
          -ImageTag "${{ github.run_number }}" `
          -RegistryName "${{ env.REGISTRY_NAME }}" `
          -MigrationScriptPaths @("${{ secrets.MIGRATION_SCRIPTS }}".Split(',')) `
          -UpgradeScriptPaths @("${{ secrets.UPGRADE_SCRIPTS }}".Split(',')) `
          -LogLevel "Info"
```

## Individual Script Usage

### Export Script

```powershell
# With SQL Authentication
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -ResourceGroupName "my-rg" `
    -ServerName "my-sql-server" `
    -DatabaseName "MyDatabase" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BacpacFileName "mydatabase.bacpac" `
    -AdminUser "sqladmin" `
    -AdminPassword "P@ssw0rd123"

# With Azure AD Authentication (recommended)
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -ResourceGroupName "my-rg" `
    -ServerName "my-sql-server" `
    -DatabaseName "MyDatabase" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BacpacFileName "mydatabase.bacpac"
```

### Build Script

```powershell
# Build from local BACPAC
.\scripts\Build-SqlContainer.ps1 `
    -BacpacPath "C:\temp\mydatabase.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -MigrationScriptPaths @("C:\scripts\migration1.sql", "C:\scripts\migration2.sql") `
    -UpgradeScriptPaths @("C:\scripts\upgrade.sql") `
    -DatabaseName "MyAppDatabase" `
    -SqlServerPassword "MyStrong@Password123"

# Build from URL
.\scripts\Build-SqlContainer.ps1 `
    -BacpacPath "https://mystorageaccount.blob.core.windows.net/bacpacs/database.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -NoCache
```

### Push Script

```powershell
# Push to ACR
.\scripts\Push-ContainerImage.ps1 `
    -RegistryName "myregistry" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -AdditionalTags @("latest", "stable")

# Push with existing Docker login
.\scripts\Push-ContainerImage.ps1 `
    -RegistryName "myregistry" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -UseExistingLogin
```

## Advanced Scenarios

### Parameterized Script Execution

```powershell
# Build with custom build arguments
$buildArgs = @{
    "CUSTOM_VAR" = "value1"
    "ENVIRONMENT" = "production"
}

.\scripts\Build-SqlContainer.ps1 `
    -BacpacPath "database.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -BuildArgs $buildArgs
```

### Multi-Environment Builds

```powershell
# Development environment
.\build.ps1 `
    -BacpacPath "dev-database.bacpac" `
    -ImageName "my-app-db-dev" `
    -ImageTag "dev-$(Get-Date -Format 'yyyyMMdd')" `
    -MigrationScriptPaths @("scripts\dev\*.sql") `
    -SkipPush

# Production environment
.\build.ps1 `
    -BacpacPath "prod-database.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "prod-v1.0.0" `
    -MigrationScriptPaths @("scripts\prod\*.sql") `
    -RegistryName "prodregistry" `
    -AdditionalTags @("latest", "stable")
```

## Error Handling

All scripts provide detailed error messages and appropriate exit codes for CI/CD integration:

- **Exit Code 0**: Success
- **Exit Code 1**: General error
- **Exit Code 2**: Parameter validation error (if implemented)

### Logging Levels

- **Debug**: Detailed diagnostic information
- **Info**: General information (default)
- **Warning**: Warning messages
- **Error**: Error messages
- **Critical**: Critical errors that stop execution

## Best Practices

1. **Use meaningful image tags**: Include version numbers or build IDs
2. **Validate scripts**: Test migration scripts in development first
3. **Use Azure AD authentication**: More secure than SQL authentication
4. **Monitor script execution**: Check logs for any warnings or errors
5. **Version control**: Keep migration scripts in version control
6. **Test containers**: Run validation tests after container build
7. **Cleanup**: Use temporary directories that are automatically cleaned up
