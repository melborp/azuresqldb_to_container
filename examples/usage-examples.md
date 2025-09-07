# Usage Examples

This document provides examples of how to use the BACPAC to Container toolkit in various scenarios.

**Important**: The toolkit uses a **multi-stage Docker build** process where:
1. **Build Stage 1**: BACPAC is imported into SQL Server during Docker build
2. **Build Stage 2**: Database files are copied to final image (BACPAC is excluded)
3. **Runtime**: Only migration scripts are executed during container startup

## Script Architecture (Updated)

The toolkit now features **modular scripts** for enhanced flexibility:

### New Modular Approach
- **Export-AzureSqlDatabase.ps1**: Database export with AccessToken authentication (exports to local file)
- **Upload-FileToBlobStorage.ps1**: Generic file upload to Azure Blob Storage
- **Build-SqlContainer.ps1**: Container build and BACPAC import
- **Push-ContainerImage.ps1**: Azure Container Registry operations

### Benefits
- ✅ **Multiple Databases**: Export several databases in parallel
- ✅ **Flexible Storage**: Upload files to different storage accounts
- ✅ **CI/CD Optimized**: Clear separation of concerns for pipeline steps
- ✅ **Reusable Components**: Use upload script for logs, backups, or any files

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

### 3. Export Only (New Modular Approach)

**New Method - Export to Local File:**
```powershell
# Export database to local file with AccessToken authentication
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -ServerName "my-sql-server" `
    -DatabaseName "MyDatabase" `
    -OutputPath "C:\temp\mydatabase.bacpac"
```

**Upload to Blob Storage:**
```powershell
# Upload the exported BACPAC to blob storage
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -FilePath "C:\temp\mydatabase.bacpac" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BlobName "mydatabase-$(Get-Date -Format 'yyyyMMdd').bacpac" `
    -Overwrite `
    -GenerateSasUrlHours 24
```

### 4. Multiple Database Export Workflow

```powershell
# Export multiple databases in parallel
$databases = @("Database1", "Database2", "Database3")
$jobs = @()

foreach ($db in $databases) {
    $scriptBlock = {
        param($SubscriptionId, $ServerName, $DatabaseName, $OutputPath)
        .\scripts\Export-AzureSqlDatabase.ps1 `
            -SubscriptionId $SubscriptionId `
            -ServerName $ServerName `
            -DatabaseName $DatabaseName `
            -OutputPath $OutputPath
    }
    
    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $subscriptionId, "my-server", $db, "C:\temp\$db.bacpac"
    $jobs += $job
}

# Wait for all exports to complete
$jobs | Wait-Job | Receive-Job

# Upload all BACPAC files
foreach ($db in $databases) {
    .\scripts\Upload-FileToBlobStorage.ps1 `
        -SubscriptionId $subscriptionId `
        -FilePath "C:\temp\$db.bacpac" `
        -StorageAccountName "mystorageaccount" `
        -ContainerName "bacpacs" `
        -Overwrite
}
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

## New Authentication Model (AccessToken)

The updated `Export-AzureSqlDatabase.ps1` script now uses **AccessToken authentication** for enhanced security:

### How It Works
1. **Azure CLI Token**: Uses `az account get-access-token --resource "https://database.windows.net/"`
2. **SqlPackage Parameters**: Includes `/AccessToken:$token` and `/ua:True` for Universal Authentication
3. **No SQL Credentials**: Eliminates the need for SQL username/password
4. **CI/CD Ready**: Works seamlessly with service principals

### Prerequisites
- Azure CLI authenticated (`az login` or service principal)
- Database permissions: `db_datareader`, `db_datawriter`, `db_ddladmin`, or `db_owner`
- Access token scoped to `https://database.windows.net/` resource

### Example Authentication Flow
```powershell
# Interactive login (development)
az login

# Export database (token automatically acquired)
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId $subId `
    -ServerName "myserver" `
    -DatabaseName "mydb" `
    -OutputPath "C:\temp\mydb.bacpac"
```

## Advanced Script Usage

### Generic File Upload Examples

The new `Upload-FileToBlobStorage.ps1` can upload any file type:

```powershell
# Upload database backup
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId $subId `
    -FilePath "C:\backups\database.bak" `
    -StorageAccountName "backupstorage" `
    -ContainerName "db-backups" `
    -ContentType "application/octet-stream"

# Upload log files with SAS URL
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId $subId `
    -FilePath "C:\logs\application.log" `
    -StorageAccountName "logstorage" `
    -ContainerName "app-logs" `
    -GenerateSasUrlHours 48 `
    -Overwrite

# Upload multiple files in batch
$files = Get-ChildItem "C:\exports\*.bacpac"
foreach ($file in $files) {
    .\scripts\Upload-FileToBlobStorage.ps1 `
        -SubscriptionId $subId `
        -FilePath $file.FullName `
        -StorageAccountName "storage" `
        -ContainerName "bacpacs" `
        -BlobName "$(Get-Date -Format 'yyyy-MM-dd')_$($file.Name)" `
        -Overwrite
}
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
    
    - name: Build Database Container (Modular Approach)
      shell: pwsh
      run: |
        # Option 1: Use main orchestrator (traditional approach)
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
          -MigrationScriptPaths @("migrations/*.sql") `
          -LogLevel "Info"

    - name: Multi-Database Export and Build (New Modular Approach)
      shell: pwsh
      run: |
        # Export multiple databases
        $databases = @("Database1", "Database2", "Database3")
        foreach ($db in $databases) {
          .\scripts\Export-AzureSqlDatabase.ps1 `
            -SubscriptionId "${{ secrets.AZURE_SUBSCRIPTION_ID }}" `
            -ServerName "${{ secrets.SQL_SERVER_NAME }}" `
            -DatabaseName $db `
            -OutputPath "temp/$db.bacpac"
          
          # Upload to blob storage
          .\scripts\Upload-FileToBlobStorage.ps1 `
            -SubscriptionId "${{ secrets.AZURE_SUBSCRIPTION_ID }}" `
            -FilePath "temp/$db.bacpac" `
            -StorageAccountName "${{ secrets.STORAGE_ACCOUNT_NAME }}" `
            -ContainerName "bacpacs" `
            -BlobName "${{ github.run_number }}_$db.bacpac" `
            -Overwrite
        }
```

### Pipeline with Separate Steps (Enhanced Control)

```yaml
# .github/workflows/modular-db-build.yml
name: Modular Database Container Build

on:
  push:
    branches: [ main ]

jobs:
  export-databases:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        database: [Database1, Database2, Database3]
    
    steps:
    - uses: actions/checkout@v3
    - uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Export ${{ matrix.database }}
      shell: pwsh
      run: |
        .\scripts\Export-AzureSqlDatabase.ps1 `
          -SubscriptionId "${{ secrets.AZURE_SUBSCRIPTION_ID }}" `
          -ServerName "${{ secrets.SQL_SERVER_NAME }}" `
          -DatabaseName "${{ matrix.database }}" `
          -OutputPath "temp/${{ matrix.database }}.bacpac"
    
    - name: Upload to Blob Storage
      shell: pwsh
      run: |
        .\scripts\Upload-FileToBlobStorage.ps1 `
          -SubscriptionId "${{ secrets.AZURE_SUBSCRIPTION_ID }}" `
          -FilePath "temp/${{ matrix.database }}.bacpac" `
          -StorageAccountName "${{ secrets.STORAGE_ACCOUNT_NAME }}" `
          -ContainerName "bacpacs" `
          -GenerateSasUrlHours 24 `
          -Overwrite
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
- Migration scripts run at container startup, not during build

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
2. Execute any migration scripts from `/opt/migration-scripts/`
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
