# Modular Scripts Documentation

This document provides detailed information about the modular scripts in the BACPAC to Container toolkit.

## Overview

The toolkit provides **modular components** for different stages of the container creation process:

| Script | Purpose | Authentication | Input/Output |
|--------|---------|----------------|--------------|
| `Export-AzureSqlDatabase.ps1` | Database export | AccessToken (Azure AD) | Database → Local BACPAC |
| `Upload-FileToBlobStorage.ps1` | File upload | Azure CLI | Local File → Blob Storage |
| `Download-FileFromBlobStorage.ps1` | File download | Azure CLI | Blob Storage → Local File |
| `Build-SqlServerImage.ps1` | Docker image build | N/A | Multiple BACPAC → Docker Image |

## Download-FileFromBlobStorage.ps1

### Purpose
Downloads files from Azure Blob Storage using Azure CLI authentication with multiple fallback methods.

### Key Features
- ✅ **Multi-Method Authentication**: Azure CLI, Storage Key, SAS Token fallbacks
- ✅ **Automatic Retry**: Multiple authentication methods for reliability
- ✅ **File Verification**: Optional integrity checking and file validation
- ✅ **Progress Reporting**: Detailed logging and size reporting
- ✅ **Force Overwrite**: Optional file replacement

### Prerequisites
- Azure CLI installed and authenticated (`az login`)
- Access to the target storage account and container
- Read permissions on the blob

### Parameters

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `BlobUrl` | Yes | Full Azure Blob Storage URL | `"https://storage.blob.core.windows.net/container/file.bacpac"` |
| `LocalPath` | Yes | Local destination path | `"C:\temp\database.bacpac"` |
| `Force` | No | Overwrite existing file | `$true` |
| `VerifyIntegrity` | No | Verify file after download | `$true` |
| `LogLevel` | No | Logging level (default: Info) | `"Debug"`, `"Info"`, `"Warning"`, `"Error"`, `"Critical"` |

### Usage Examples

**Basic Download:**
```powershell
.\scripts\Download-FileFromBlobStorage.ps1 `
    -BlobUrl "https://mystorageaccount.blob.core.windows.net/bacpacs/database.bacpac" `
    -LocalPath "C:\temp\database.bacpac"
```

**Download with Verification:**
```powershell
.\scripts\Download-FileFromBlobStorage.ps1 `
    -BlobUrl "https://mystorageaccount.blob.core.windows.net/bacpacs/database.bacpac" `
    -LocalPath "C:\temp\database.bacpac" `
    -Force `
    -VerifyIntegrity
```

### Authentication Methods
1. **Azure CLI Authentication** (Primary): Uses current Azure CLI session
2. **Storage Account Key** (Fallback): Retrieves and uses storage account key
3. **SAS Token Generation** (Last Resort): Creates temporary SAS token

## Build-SqlServerImage.ps1

### Purpose
Builds a Docker image with multiple BACPAC files imported during build time and support for runtime migration scripts.

### Key Features
- ✅ **Multiple BACPAC Support**: Import multiple databases in a single image
- ✅ **Build-Time Import**: BACPAC files imported during Docker build (not in final image)
- ✅ **Runtime Migration Scripts**: Scripts mounted as volumes and executed at startup
- ✅ **Multi-Stage Build**: Optimized image size with separate build and runtime stages
- ✅ **Automatic Database Naming**: Smart naming from BACPAC filenames or custom names
- ✅ **Manifest Generation**: Build information and usage documentation

### Prerequisites
- Docker installed and running
- Local BACPAC files (use Download-FileFromBlobStorage.ps1 to obtain them)
- Optional: Migration script files
- Sufficient disk space for Docker build process

### Parameters

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `ImageName` | Yes | Docker image name | `"my-sql-app"` |
| `ImageTag` | Yes | Docker image tag | `"v1.0.0"` |
| `BacpacPaths` | Yes | Array of BACPAC file paths | `@("C:\temp\db1.bacpac", "C:\temp\db2.bacpac")` |
| `DatabaseNames` | No | Custom database names | `@("Database1", "Database2")` |
| `MigrationScriptPaths` | No | Migration script paths | `@("C:\scripts\*.sql")` |
| `SqlServerPassword` | No | SA password (SecureString) | `(ConvertTo-SecureString "MyPassword" -AsPlainText -Force)` |
| `MigrationMountPath` | No | Container path for mounted scripts | `"/var/opt/mssql/migration-scripts"` |
| `NoCache` | No | Build without Docker cache | `$true` |
| `LogLevel` | No | Logging level (default: Info) | `"Debug"`, `"Info"`, `"Warning"`, `"Error"`, `"Critical"` |

### Usage Examples

**Single Database Build:**
```powershell
.\scripts\Build-SqlServerImage.ps1 `
    -ImageName "my-sql-app" `
    -ImageTag "v1.0.0" `
    -BacpacPaths @("C:\temp\myapp.bacpac")
```

**Multi-Database Build with Migration Scripts:**
```powershell
$securePassword = ConvertTo-SecureString "MySecurePassword123!" -AsPlainText -Force

.\scripts\Build-SqlServerImage.ps1 `
    -ImageName "multi-db-app" `
    -ImageTag "v2.0.0" `
    -BacpacPaths @("C:\temp\app.bacpac", "C:\temp\config.bacpac") `
    -DatabaseNames @("AppDatabase", "ConfigDatabase") `
    -MigrationScriptPaths @("C:\migrations\*.sql") `
    -SqlServerPassword $securePassword
```

**Running the Built Image:**
```bash
# Basic run
docker run -d -p 1433:1433 -e SA_PASSWORD='YourPassword' my-sql-app:v1.0.0

# With migration scripts mounted
docker run -d -p 1433:1433 \
  -e SA_PASSWORD='YourPassword' \
  -v /path/to/migration-scripts:/var/opt/mssql/migration-scripts \
  multi-db-app:v2.0.0
```

### Build Process
1. **Validation**: Checks BACPAC files and migration scripts
2. **Database Naming**: Assigns names based on filenames or custom names
3. **Build Context**: Creates temporary directory with all required files
4. **Dockerfile Generation**: Creates multi-stage Dockerfile for efficient building
5. **Multi-Stage Build**:
   - **Stage 1 (importer)**: Installs SqlPackage and imports all BACPAC files
   - **Stage 2 (runtime)**: Copies imported databases and sets up runtime environment
6. **Startup Script**: Configures runtime migration script execution
7. **Cleanup**: Removes temporary build context

## Export-AzureSqlDatabase.ps1

### Purpose
Exports an Azure SQL Database to BACPAC format using SqlPackage utility with AccessToken authentication.

### Key Features
- ✅ **AccessToken Authentication**: Uses Azure AD tokens for secure database access
- ✅ **Universal Authentication**: Includes `/ua:True` parameter for SqlPackage
- ✅ **Local Output**: Exports directly to specified file path
- ✅ **Multiple Databases**: Designed for exporting multiple databases efficiently
- ✅ **CI/CD Optimized**: Works seamlessly with service principals

### Prerequisites
- SqlPackage utility installed and in PATH
- Azure CLI authenticated (`az login` or service principal)
- Valid access token for `https://database.windows.net/` resource scope
- Database permissions: `db_datareader`, `db_datawriter`, `db_ddladmin`, or `db_owner`

### Parameters

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `SubscriptionId` | Yes | Azure subscription ID | `"12345678-1234-1234-1234-123456789abc"` |
| `ServerName` | Yes | SQL server name (FQDN or short name) | `"myserver"` or `"myserver.database.windows.net"` |
| `DatabaseName` | Yes | Database name to export | `"MyDatabase"` |
| `OutputPath` | Yes | Output path for BACPAC file | `"C:\temp\database.bacpac"` |
| `TenantId` | No | Azure AD tenant ID (auto-detected if not provided) | `"87654321-4321-4321-4321-210987654321"` |
| `LogLevel` | No | Logging level (default: Info) | `"Debug"`, `"Info"`, `"Warning"`, `"Error"`, `"Critical"` |

### Usage Examples

**Basic Export:**
```powershell
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -ServerName "myserver" `
    -DatabaseName "MyDatabase" `
    -OutputPath "C:\temp\mydatabase.bacpac"
```

**Multiple Database Export:**
```powershell
$databases = @("Database1", "Database2", "Database3")
foreach ($db in $databases) {
    .\scripts\Export-AzureSqlDatabase.ps1 `
        -SubscriptionId $subscriptionId `
        -ServerName "myserver" `
        -DatabaseName $db `
        -OutputPath "C:\exports\$db.bacpac" `
        -LogLevel "Debug"
}
```

**Parallel Export (PowerShell Jobs):**
```powershell
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
    
    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $subscriptionId, "myserver", $db, "C:\exports\$db.bacpac"
    $jobs += $job
}

# Wait for all exports to complete
$jobs | Wait-Job | Receive-Job
```

### Authentication Details

The script uses **AccessToken authentication** which:

1. **Acquires Token**: Uses `az account get-access-token --resource "https://database.windows.net/"`
2. **SqlPackage Parameters**: Includes `/AccessToken:$token` and `/ua:True`
3. **Security**: No SQL credentials required
4. **Permissions**: Leverages Azure AD database permissions

### Output

The script outputs:
- **BACPAC File**: Created at the specified `OutputPath`
- **Automation Variables**: For CI/CD integration
  ```
  BACPAC_PATH=C:\temp\mydatabase.bacpac
  BACPAC_FILENAME=mydatabase.bacpac
  BACPAC_SIZE_MB=150.25
  BACPAC_SIZE_BYTES=157524480
  ```

---

## Upload-FileToBlobStorage.ps1

### Purpose
Uploads any file to Azure Blob Storage using Azure CLI. Designed for generic file upload scenarios.

### Key Features
- ✅ **Generic Upload**: Works with BACPAC, logs, backups, or any file type
- ✅ **Container Management**: Creates containers if they don't exist
- ✅ **Overwrite Protection**: Optional overwrite flag for safety
- ✅ **SAS URL Generation**: Optional secure download links
- ✅ **Content Type Detection**: Automatic content type detection
- ✅ **Upload Verification**: Verifies file size and properties after upload
- ✅ **Performance Metrics**: Shows upload duration and throughput

### Prerequisites
- Azure CLI authenticated (`az login` or service principal)
- Storage account access permissions:
  - `Storage Blob Data Contributor` role, or
  - `Microsoft.Storage/storageAccounts/blobServices/containers/read`
  - `Microsoft.Storage/storageAccounts/blobServices/containers/write`

### Parameters

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `SubscriptionId` | Yes | Azure subscription ID | `"12345678-1234-1234-1234-123456789abc"` |
| `FilePath` | Yes | Local file path to upload | `"C:\temp\database.bacpac"` |
| `StorageAccountName` | Yes | Storage account name | `"mystorageaccount"` |
| `ContainerName` | Yes | Storage container name | `"bacpacs"` |
| `BlobName` | No | Blob name (defaults to filename) | `"mydatabase-20250907.bacpac"` |
| `Overwrite` | No | Overwrite existing blob | Switch parameter |
| `GenerateSasUrlHours` | No | Generate SAS URL (hours, default: 0) | `24` |
| `ContentType` | No | Content type (auto-detected if not provided) | `"application/octet-stream"` |
| `LogLevel` | No | Logging level (default: Info) | `"Debug"`, `"Info"`, `"Warning"`, `"Error"`, `"Critical"` |

### Usage Examples

**Basic Upload:**
```powershell
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -FilePath "C:\temp\database.bacpac" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -Overwrite
```

**Upload with SAS URL:**
```powershell
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId $subscriptionId `
    -FilePath "C:\temp\database.bacpac" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BlobName "database-$(Get-Date -Format 'yyyyMMdd').bacpac" `
    -GenerateSasUrlHours 24 `
    -Overwrite
```

**Batch Upload:**
```powershell
$files = Get-ChildItem "C:\exports\*.bacpac"
foreach ($file in $files) {
    .\scripts\Upload-FileToBlobStorage.ps1 `
        -SubscriptionId $subscriptionId `
        -FilePath $file.FullName `
        -StorageAccountName "mystorageaccount" `
        -ContainerName "bacpacs" `
        -Overwrite
}
```

## Common Workflows

### Complete Database-to-Container Workflow

**1. Export Database to BACPAC:**
```powershell
# Export from Azure SQL Database
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -ServerName "myserver" `
    -DatabaseName "MyDatabase" `
    -OutputPath "C:\temp\myapp.bacpac"
```

**2. Upload to Blob Storage (Optional):**
```powershell
# Upload for sharing or backup
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId "12345678-1234-1234-1234-123456789abc" `
    -FilePath "C:\temp\myapp.bacpac" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -Overwrite
```

**3. Download BACPAC Files (if needed):**
```powershell
# Download multiple BACPAC files
.\scripts\Download-FileFromBlobStorage.ps1 `
    -BlobUrl "https://mystorageaccount.blob.core.windows.net/bacpacs/app.bacpac" `
    -LocalPath "C:\build\app.bacpac" `
    -Force

.\scripts\Download-FileFromBlobStorage.ps1 `
    -BlobUrl "https://mystorageaccount.blob.core.windows.net/bacpacs/config.bacpac" `
    -LocalPath "C:\build\config.bacpac" `
    -Force
```

**4. Build Docker Image:**
```powershell
# Create multi-database container
$securePassword = ConvertTo-SecureString "MySecurePassword123!" -AsPlainText -Force

.\scripts\Build-SqlServerImage.ps1 `
    -ImageName "my-application" `
    -ImageTag "v1.0.0" `
    -BacpacPaths @("C:\build\app.bacpac", "C:\build\config.bacpac") `
    -DatabaseNames @("ApplicationDB", "ConfigDB") `
    -MigrationScriptPaths @("C:\migrations\*.sql") `
    -SqlServerPassword $securePassword
```

**5. Run Container:**
```bash
docker run -d -p 1433:1433 \
  -e SA_PASSWORD='MySecurePassword123!' \
  -v /path/to/runtime-migrations:/var/opt/mssql/migration-scripts \
  my-application:v1.0.0
```

### CI/CD Pipeline Integration

**Azure DevOps Pipeline Example:**
```yaml
stages:
- stage: BuildDatabase
  jobs:
  - job: ExportAndBuild
    steps:
    - task: PowerShell@2
      displayName: 'Export Database'
      inputs:
        filePath: 'scripts/Export-AzureSqlDatabase.ps1'
        arguments: |
          -SubscriptionId $(SUBSCRIPTION_ID)
          -ServerName $(SQL_SERVER_NAME)
          -DatabaseName $(DATABASE_NAME)
          -OutputPath "$(Build.ArtifactStagingDirectory)/database.bacpac"
    
    - task: PowerShell@2
      displayName: 'Build Docker Image'
      inputs:
        filePath: 'scripts/Build-SqlServerImage.ps1'
        arguments: |
          -ImageName $(IMAGE_NAME)
          -ImageTag $(Build.BuildNumber)
          -BacpacPaths @("$(Build.ArtifactStagingDirectory)/database.bacpac")
          -SqlServerPassword $(ConvertTo-SecureString "$(SQL_PASSWORD)" -AsPlainText -Force)
    
    - task: Docker@2
      displayName: 'Push Image'
      inputs:
        command: 'push'
        repository: $(IMAGE_NAME)
        tags: $(Build.BuildNumber)
```

**GitHub Actions Example:**
```yaml
name: Build SQL Container
on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: windows-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Export Database
      run: |
        .\scripts\Export-AzureSqlDatabase.ps1 `
          -SubscriptionId "${{ secrets.SUBSCRIPTION_ID }}" `
          -ServerName "${{ secrets.SQL_SERVER_NAME }}" `
          -DatabaseName "${{ secrets.DATABASE_NAME }}" `
          -OutputPath "database.bacpac"
    
    - name: Build Docker Image
      run: |
        $securePassword = ConvertTo-SecureString "${{ secrets.SQL_PASSWORD }}" -AsPlainText -Force
        .\scripts\Build-SqlServerImage.ps1 `
          -ImageName "my-app" `
          -ImageTag "${{ github.run_number }}" `
          -BacpacPaths @("database.bacpac") `
          -SqlServerPassword $securePassword
```

## Migration Scripts

### Runtime Migration Script Execution

Migration scripts are executed at container startup and should be mounted as volumes:

**Directory Structure:**
```
/migration-scripts/
├── 001_create_indexes.sql
├── 002_update_schema.sql
├── 003_seed_data.sql
└── ...
```

**Script Naming Convention:**
- Use numeric prefixes (001_, 002_, etc.) for execution order
- Use descriptive names for the operation
- Keep scripts idempotent (safe to run multiple times)

**Example Migration Script:**
```sql
-- 001_create_performance_indexes.sql
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Orders_CustomerID')
BEGIN
    CREATE INDEX IX_Orders_CustomerID ON Orders(CustomerID);
    PRINT 'Created index IX_Orders_CustomerID';
END
ELSE
BEGIN
    PRINT 'Index IX_Orders_CustomerID already exists';
END
```

### Best Practices

**For Export-AzureSqlDatabase.ps1:**
- Use service principal authentication in CI/CD pipelines
- Export during off-peak hours for large databases
- Monitor export progress with Debug log level for large databases
- Ensure sufficient disk space for BACPAC files

**For Download-FileFromBlobStorage.ps1:**
- Use `-VerifyIntegrity` for critical files
- Implement retry logic in scripts for network issues
- Use `-Force` carefully in automated scenarios

**For Build-SqlServerImage.ps1:**
- Use SecureString for passwords in scripts
- Keep BACPAC files locally during build for faster access
- Test migration scripts independently before container build
- Use multi-stage builds to keep final image size minimal

**For Container Deployment:**
- Always use strong passwords in production
- Mount migration scripts as read-only volumes
- Monitor container startup logs for migration script execution
- Use health checks to verify database availability
- Consider using init containers for complex migration workflows

## Troubleshooting

### Common Issues

**Authentication Failures:**
```powershell
# Check Azure CLI authentication
az account show

# Re-authenticate if needed
az login

# For service principals
az login --service-principal -u $clientId -p $clientSecret --tenant $tenantId
```

**BACPAC Import Failures:**
- Verify BACPAC file integrity
- Check available disk space in container
- Ensure SA_PASSWORD meets complexity requirements
- Review SqlPackage error messages in build logs

**Migration Script Issues:**
- Verify script syntax with SQL Server Management Studio
- Test scripts on a copy of the database first
- Check file permissions on mounted volumes
- Review container logs for script execution details

**Docker Build Issues:**
- Clear Docker build cache with `--no-cache`
- Verify available disk space for Docker builds
- Check Docker daemon status and restart if needed
- Review Dockerfile syntax and multi-stage build configuration
    .\scripts\Upload-FileToBlobStorage.ps1 `
        -SubscriptionId $subscriptionId `
        -FilePath $file.FullName `
        -StorageAccountName "mystorageaccount" `
        -ContainerName "bacpacs" `
        -BlobName "$(Get-Date -Format 'yyyy-MM-dd')_$($file.Name)" `
        -Overwrite
}
```

**Upload Different File Types:**
```powershell
# Upload log file
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId $subscriptionId `
    -FilePath "C:\logs\application.log" `
    -StorageAccountName "logstorage" `
    -ContainerName "app-logs" `
    -ContentType "text/plain"

# Upload backup file
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId $subscriptionId `
    -FilePath "C:\backups\database.bak" `
    -StorageAccountName "backupstorage" `
    -ContainerName "db-backups" `
    -ContentType "application/octet-stream"
```

### Content Type Detection

The script automatically detects content types:

| File Extension | Content Type |
|----------------|--------------|
| `.bacpac` | `application/octet-stream` |
| `.sql` | `text/plain` |
| `.json` | `application/json` |
| `.xml` | `application/xml` |
| `.txt`, `.log` | `text/plain` |
| `.zip` | `application/zip` |
| `.tar` | `application/x-tar` |
| `.gz` | `application/gzip` |
| `default` | `application/octet-stream` |

### Output

The script outputs:
- **Blob URL**: Public URL to the uploaded blob
- **SAS URL**: Secure download URL (if requested)
- **Automation Variables**: For CI/CD integration
  ```
  BLOB_URL=https://storage.blob.core.windows.net/container/file.bacpac
  BLOB_NAME=file.bacpac
  BLOB_SIZE_MB=150.25
  BLOB_SIZE_BYTES=157524480
  UPLOAD_DURATION_SECONDS=45.67
  BLOB_SAS_URL=https://storage.blob.core.windows.net/container/file.bacpac?sv=...
  SAS_EXPIRY_HOURS=24
  ```

---

## Migration from Legacy Script

### Before (Legacy Approach)
```powershell
# Old Export-AzureSqlDatabase.ps1 (export + upload in one script)
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId $subId `
    -ResourceGroupName "my-rg" `
    -ServerName "myserver" `
    -DatabaseName "MyDatabase" `
    -StorageAccountName "storage" `
    -ContainerName "bacpacs" `
    -BacpacFileName "database.bacpac"
```

### After (New Modular Approach)
```powershell
# Step 1: Export database to local file
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId $subId `
    -ServerName "myserver" `
    -DatabaseName "MyDatabase" `
    -OutputPath "C:\temp\database.bacpac"

# Step 2: Upload file to blob storage
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId $subId `
    -FilePath "C:\temp\database.bacpac" `
    -StorageAccountName "storage" `
    -ContainerName "bacpacs" `
    -Overwrite
```

### Benefits of New Approach
- ✅ **Flexibility**: Export multiple databases, upload to different storage accounts
- ✅ **Reusability**: Use upload script for any file type
- ✅ **Parallel Processing**: Export multiple databases simultaneously
- ✅ **Error Isolation**: Separate failure points for easier troubleshooting
- ✅ **CI/CD Integration**: Better pipeline step separation

---

## Best Practices

### Security
- Use **Azure AD authentication** instead of SQL credentials
- Leverage **service principals** in CI/CD environments
- Generate **time-limited SAS URLs** for secure file sharing
- Rotate access tokens regularly

### Performance
- Export **multiple databases in parallel** using PowerShell jobs
- Use **local storage** for temporary files to reduce network overhead
- Monitor **upload throughput** and adjust based on file sizes
- Consider **compression** for large BACPAC files

### Error Handling
- Check **exit codes** and automation variables
- Enable **debug logging** for troubleshooting
- Implement **retry logic** for network operations
- Validate **file integrity** after uploads

### CI/CD Integration
- Use **separate pipeline steps** for export and upload
- Store **sensitive parameters** in secret management systems
- Implement **parallel matrix builds** for multiple databases
- Generate **unique blob names** using build numbers or timestamps
