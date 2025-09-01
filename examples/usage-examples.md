# Usage Examples

This document provides examples of how to use the BACPAC to Container toolkit in various scenarios.

**Important**: The toolkit uses a **multi-stage Docker build** process where:
1. **Build Stage 1**: BACPAC is imported into SQL Server during Docker build
2. **Build Stage 2**: Database files are copied to final image (BACPAC is excluded)
3. **Runtime**: Only migration and upgrade scripts are executed during container startup

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

### 2. Build from Existing BACPAC (Optimized Image)

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
*Note: The final image will NOT contain the BACPAC file, significantly reducing image size.*

### 3. Export Only

```powershell
# With Azure AD Authentication (recommended)
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -ResourceGroupName "my-rg" `
    -ServerName "my-sql-server" `
    -DatabaseName "MyDatabase" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BacpacFileName "mydatabase.bacpac"

# With SQL Authentication (if Azure AD is not available)
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
```

**Note**: This script now uses SqlPackage utility which supports Azure AD authentication. No SQL credentials required when using Azure AD!

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
- task: AzureCLI@2
  displayName: 'Export Database and Build Container'
  inputs:
    azureSubscription: 'your-service-connection'  # Service connection name
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
      -ImageName $(imageName)
      -ImageTag $(imageTag)
      -RegistryName $(registryName)
      -MigrationScriptPaths $(MIGRATION_SCRIPTS)
      -UpgradeScriptPaths $(UPGRADE_SCRIPTS)
      -LogLevel "Info"
```

**Note**: The AzureCLI@2 task automatically handles service principal authentication, making the scripts run without prompts.

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
    -BacpacFileName "mydatabase.bacpac" `
    -TenantId "your-tenant-id"  # Optional - will be auto-detected if omitted
```

### Build Script

```powershell
# Build from local BACPAC (BACPAC imported during build, excluded from final image)
.\scripts\Build-SqlContainer.ps1 `
    -BacpacPath "C:\temp\mydatabase.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -MigrationScriptPaths @("C:\scripts\migration1.sql", "C:\scripts\migration2.sql") `
    -UpgradeScriptPaths @("C:\scripts\upgrade.sql") `
    -DatabaseName "MyAppDatabase" `
    -SqlServerPassword "MyStrong@Password123"

# Build from URL (BACPAC downloaded and imported during build)
.\scripts\Build-SqlContainer.ps1 `
    -BacpacPath "https://mystorageaccount.blob.core.windows.net/bacpacs/database.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -NoCache
```

**Key Points:**
- BACPAC is imported during Docker build stage 1
- Final image (stage 2) contains only the database files, not the BACPAC
- Migration and upgrade scripts run at container startup, not during build

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

## Running the Container Locally

After building your container image, you can run it locally for testing and development.

### Basic Container Run

```bash
# Run the container with port mapping
docker run -d -p 1433:1433 \
  -e SA_PASSWORD="YourStrong@Passw0rd123" \
  --name my-sql-container \
  my-app-db:v1.0.0
```

```powershell
# PowerShell equivalent
docker run -d -p 1433:1433 `
  -e SA_PASSWORD="YourStrong@Passw0rd123" `
  --name my-sql-container `
  my-app-db:v1.0.0
```

### Connecting to the Container

Once the container is running, you can connect using any SQL Server client:

```bash
# Using sqlcmd (if mssql-tools is installed locally)
sqlcmd -S localhost,1433 -U sa -P "YourStrong@Passw0rd123" -d ImportedDatabase

# Using Azure Data Studio connection string
Server: localhost,1433
Authentication: SQL Login
User: sa
Password: YourStrong@Passw0rd123
Database: ImportedDatabase
```

### Container Management

```bash
# Check container status
docker ps

# View container logs
docker logs my-sql-container

# Stop the container
docker stop my-sql-container

# Remove the container
docker rm my-sql-container

# Connect to running container for debugging
docker exec -it my-sql-container /bin/bash
```

### Testing with Custom Environment Variables

```bash
# Run with custom database name and password
docker run -d -p 1433:1433 \
  -e SA_PASSWORD="MyCustomPassword123!" \
  -e DATABASE_NAME="MyCustomDatabase" \
  --name test-sql-custom \
  my-app-db:v1.0.0
```

### Volume Mounting for Persistent Data

```bash
# Mount a volume for persistent database storage
docker run -d -p 1433:1433 \
  -e SA_PASSWORD="YourStrong@Passw0rd123" \
  -v sql_data:/var/opt/mssql \
  --name persistent-sql \
  my-app-db:v1.0.0
```

**Note**: The container will:
1. Start SQL Server
2. Execute any migration scripts from `/var/opt/mssql/scripts/`
3. Keep SQL Server running and ready for connections

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
3. **Use Azure AD authentication**: More secure than SQL authentication for exports
4. **Monitor script execution**: Check logs for any warnings or errors during startup
5. **Version control**: Keep migration scripts in version control
6. **Test containers**: Run validation tests after container build
7. **Cleanup**: Use temporary directories that are automatically cleaned up
8. **Optimize image size**: The multi-stage build automatically excludes BACPAC from final image
9. **Fast migration scripts**: Keep startup scripts lightweight as they run during container startup
10. **Idempotent scripts**: Ensure migration scripts can be run multiple times safely
