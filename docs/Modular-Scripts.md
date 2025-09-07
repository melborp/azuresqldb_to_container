# Modular Scripts Documentation

This document provides detailed information about the new modular scripts introduced in the BACPAC to Container toolkit.

## Overview

The toolkit has been enhanced with **split functionality** to provide better modularity and flexibility:

| Script | Purpose | Authentication | Output |
|--------|---------|----------------|--------|
| `Export-AzureSqlDatabase.ps1` | Database export only | AccessToken (Azure AD) | Local BACPAC file |
| `Upload-FileToBlobStorage.ps1` | Generic file upload | Azure CLI | Blob Storage |

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
