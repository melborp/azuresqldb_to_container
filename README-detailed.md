# BACPAC to Container Toolkit

A comprehensive PowerShell-based automation toolkit for exporting Azure SQL Databases to BACPAC format, importing them into SQL Server containers, executing migration scripts, and publishing to Azure Container Registry.

## 🚀 Features

- **Azure SQL Database Export**: Export databases to BACPAC format with Azure Blob Storage integration
- **Build-Time Database Import**: Import BACPAC during Docker build process for optimized final image
- **Migration Script Execution**: Run custom migration scripts during container startup
- **Optimized Image Size**: Final container excludes BACPAC file, containing only the imported database
- **Fail-Fast Validation**: Container build fails if BACPAC import fails; runtime fails if any script fails
- **CI/CD Ready**: Parameter-driven scripts designed for pipeline integration
- **Cross-Platform**: PowerShell Core compatible (Windows, Linux, macOS)
- **Comprehensive Logging**: Structured logging with configurable levels
- **Azure Container Registry**: Automated image tagging and publishing
- **Simplified Architecture**: Single migration script directory for easier management

## 📋 Prerequisites

- **PowerShell 7.x+** (PowerShell Core)
- **Azure CLI** with active login session
- **SqlPackage Utility** for database export operations ([Installation Guide](docs/SqlPackage-Installation.md))
- **Docker** (Desktop or Engine)
- **Azure Subscription** with appropriate permissions

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Azure SQL     │───▶│   Azure Blob     │───▶│ Docker Build    │
│   Database      │    │   Storage        │    │ Stage 1: Import │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐                           ┌─────────────────┐
│  Migration SQL  │                           │ Docker Build    │
│    Scripts      │────────────────────────▶ │ Stage 2: Final  │
└─────────────────┘                           └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Azure ACR     │◀───│  Runtime: Only   │◀───│  Final Image    │
│                 │    │ Migration Scripts│    │ (No BACPAC)     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

**Key Process:**
1. **Build Stage 1**: Import BACPAC into SQL Server during Docker build
2. **Build Stage 2**: Copy database files to final image (excludes BACPAC)
3. **Runtime**: Execute migration scripts on container startup

## 🔐 Required Permissions

### Azure SQL Database Permissions

To export a database, your Azure AD account needs these database-level permissions:

```sql
-- Replace 'your-email@domain.com' with your actual Azure AD email
CREATE USER [your-email@domain.com] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [your-email@domain.com];
ALTER ROLE db_datawriter ADD MEMBER [your-email@domain.com];
ALTER ROLE db_owner ADD MEMBER [your-email@domain.com]; -- For export operations
```

**Note**: These permissions must be granted by a database administrator or someone with `db_owner` role.

For detailed permission setup instructions, see [Required Permissions Guide](docs/Required-Permissions.md).

### Azure Blob Storage Permissions

Your Azure AD account needs these storage permissions:

- **Storage Blob Data Contributor** role on the storage account or container
- Or the following RBAC permissions:
  - `Microsoft.Storage/storageAccounts/blobServices/containers/read`
  - `Microsoft.Storage/storageAccounts/blobServices/containers/write`
  - `Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action`

### Azure Container Registry Permissions

For pushing images to ACR:

- **AcrPush** role on the container registry
- Or **Contributor** role if you need to create repositories

## 🛠️ Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd bacpac_to_container
   ```

2. **Ensure prerequisites are installed**:
   ```powershell
   # Check PowerShell version
   $PSVersionTable.PSVersion
   
   # Check Azure CLI
   az --version
   
   # Check SqlPackage
   sqlpackage /version
   
   # Check Docker
   docker --version
   ```

3. **Authentication setup**:
   - **Development**: `az login` for interactive Azure AD authentication
   - **CI/CD**: Use service principal via Azure CLI task/action ([CI/CD Guide](docs/CI-CD-Authentication.md))
   - **Fallback**: SQL authentication with `-AdminUser` and `-AdminPassword`

3. **Login to Azure**:
   ```bash
   az login
   ```

## 📖 Quick Start

### Complete Process (Export → Build → Push)

```powershell
.\build.ps1 `
    -SubscriptionId "your-subscription-id" `
    -ResourceGroupName "my-resource-group" `
    -ServerName "my-sql-server" `
    -DatabaseName "MyDatabase" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BacpacFileName "mydatabase.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -RegistryName "myregistry" `
    -MigrationScriptPaths @("path\to\migration1.sql", "path\to\migration2.sql")
```

### Build from Existing BACPAC

```powershell
.\build.ps1 `
    -BacpacPath "https://mystorageaccount.blob.core.windows.net/bacpacs/database.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -SkipExport `
    -SkipPush `
    -MigrationScriptPaths @("migrations\*.sql")
```

## 📁 Project Structure

```
bacpac_to_container/
├── scripts/
│   ├── Export-AzureSqlDatabase.ps1    # Azure SQL Database export (AccessToken auth)
│   ├── Upload-FileToBlobStorage.ps1   # Generic file upload to Azure Blob Storage
│   ├── Build-SqlContainer.ps1         # Container build with BACPAC import
│   ├── Push-ContainerImage.ps1        # Azure Container Registry push
│   └── common/
│       ├── Logging-Helpers.ps1        # Structured logging utilities
│       ├── Azure-Helpers.ps1          # Azure-specific functions
│       └── Docker-Helpers.ps1         # Docker management functions
├── docker/
│   ├── Dockerfile                     # Multi-stage SQL Server container
│   ├── import-bacpac.sh               # BACPAC import during build stage
│   └── entrypoint.sh                  # Container startup script (migration only)
├── examples/
│   ├── sample-migration.sql           # Example migration script
│   ├── usage-examples.md             # Comprehensive usage examples
│   └── sample-ci-pipeline.yml        # CI/CD pipeline examples
├── docs/
│   ├── Required-Permissions.md       # Detailed permissions setup guide
│   ├── CI-CD-Authentication.md       # CI/CD authentication guide
│   ├── SqlPackage-Installation.md    # SqlPackage installation instructions
│   └── Modular-Scripts.md           # New modular scripts documentation
├── build.ps1                         # Main orchestrator script
├── Agents.md                         # Project requirements and design
├── README.md                         # This file
└── .gitignore                        # Git ignore patterns
```

## 🔧 Individual Script Usage

### 1. Export Azure SQL Database (New Focused Version)

Export to local file:
```powershell
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId "your-subscription-id" `
    -ServerName "my-sql-server" `
    -DatabaseName "MyDatabase" `
    -OutputPath "C:\temp\database.bacpac"
```

### 2. Upload File to Blob Storage (New Generic Upload)

Upload any file to Azure Blob Storage:
```powershell
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId "your-subscription-id" `
    -FilePath "C:\temp\database.bacpac" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BlobName "database-$(Get-Date -Format 'yyyyMMdd').bacpac" `
    -Overwrite `
    -GenerateSasUrlHours 24
```

### 3. Complete Export and Upload Workflow

For multiple databases or advanced scenarios:
```powershell
# Export multiple databases
.\scripts\Export-AzureSqlDatabase.ps1 -SubscriptionId $subId -ServerName "server1" -DatabaseName "db1" -OutputPath "C:\temp\db1.bacpac"
.\scripts\Export-AzureSqlDatabase.ps1 -SubscriptionId $subId -ServerName "server1" -DatabaseName "db2" -OutputPath "C:\temp\db2.bacpac"

# Upload all BACPAC files
.\scripts\Upload-FileToBlobStorage.ps1 -SubscriptionId $subId -FilePath "C:\temp\db1.bacpac" -StorageAccountName "storage1" -ContainerName "bacpacs"
.\scripts\Upload-FileToBlobStorage.ps1 -SubscriptionId $subId -FilePath "C:\temp\db2.bacpac" -StorageAccountName "storage1" -ContainerName "bacpacs"
```

### 4. Build SQL Container

```powershell
.\scripts\Build-SqlContainer.ps1 `
    -BacpacPath "path\to\database.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -MigrationScriptPaths @("script1.sql", "script2.sql")
```

### 5. Push to Azure Container Registry

```powershell
.\scripts\Push-ContainerImage.ps1 `
    -RegistryName "myregistry" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -AdditionalTags @("latest", "stable")
```

## 🔄 Script Architecture Benefits

### Modular Design
The toolkit now features **split functionality** for enhanced flexibility:

**Export-AzureSqlDatabase.ps1**:
- ✅ **Focused Purpose**: Database export only with AccessToken authentication
- ✅ **Local Output**: Exports directly to specified file path
- ✅ **Multiple Databases**: Easily export multiple databases in parallel
- ✅ **CI/CD Optimized**: Perfect for automated pipelines

**Upload-FileToBlobStorage.ps1**:
- ✅ **Generic Upload**: Upload any file type to Azure Blob Storage
- ✅ **Multiple Targets**: Upload same file to different storage accounts
- ✅ **SAS URL Generation**: Optional secure download links
- ✅ **Upload Verification**: Automatic file integrity checks

### Authentication Model
- **AccessToken Authentication**: Uses Azure AD tokens via `az account get-access-token --resource "https://database.windows.net/"`
- **Universal Authentication**: SqlPackage parameter `/ua:True` for proper token recognition
- **Security**: No SQL credentials required, leverages Azure AD permissions
- **CI/CD Ready**: Works seamlessly with service principals in automated environments

## 🔄 CI/CD Integration

The toolkit is designed for seamless CI/CD integration:

### Azure DevOps

```yaml
- task: PowerShell@2
  displayName: 'Build Database Container'
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
      -ImageName $(IMAGE_NAME)
      -ImageTag $(Build.BuildNumber)
      -RegistryName $(REGISTRY_NAME)
      -MigrationScriptPaths $(MIGRATION_SCRIPTS)
```

### GitHub Actions

```yaml
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
      -RegistryName "${{ env.REGISTRY_NAME }}"
```

## 📝 Script Parameters

### Main Orchestrator (`build.ps1`)

| Parameter | Required | Description |
|-----------|----------|-------------|
| `SubscriptionId` | No* | Azure subscription ID |
| `ResourceGroupName` | No* | Resource group containing SQL server |
| `ServerName` | No* | SQL server name |
| `DatabaseName` | No* | Database to export |
| `StorageAccountName` | No* | Storage account for BACPAC |
| `ContainerName` | No* | Storage container name |
| `BacpacFileName` | No* | BACPAC file name |
| `BacpacPath` | No | Path/URL to existing BACPAC |
| `ImageName` | **Yes** | Docker image name |
| `ImageTag` | **Yes** | Docker image tag |
| `MigrationScriptPaths` | No | Array of migration script paths |
| `RegistryName` | No* | Azure Container Registry name |
| `SkipExport` | No | Skip database export |
| `SkipBuild` | No | Skip container build |
| `SkipPush` | No | Skip container push |

*Required unless corresponding step is skipped

## 🔐 Security Considerations

- **No Secrets in Code**: All sensitive data passed as parameters
- **Azure AD Authentication**: Fully supported via SqlPackage - preferred over SQL authentication
- **Least Privilege**: Scripts request only necessary permissions
- **Audit Logging**: All operations logged for compliance
- **Credential Isolation**: Use CI/CD secret management

## 🏗️ Migration Script Guidelines

Migration scripts run during **container startup** (not during build) and should follow these guidelines:

1. **Idempotent**: Safe to run multiple times
2. **Transactional**: Use transactions where appropriate
3. **Validated**: Test thoroughly before use
4. **Ordered**: Use naming conventions for execution order (scripts are executed alphabetically)
5. **Logged**: Include PRINT statements for debugging
6. **Fast Execution**: Keep scripts lightweight as they run during container startup

### Script Execution Order

1. **Build Time**: BACPAC import (automatic, no custom scripts)
2. **Runtime**: Migration scripts (executed during container startup)

### Script Location

Migration scripts are copied to `/opt/migration-scripts/` in the container and executed in alphabetical order.

### Running the Container

After building your container image, you can run it locally for testing:

```bash
# Run the container with port mapping
docker run -d -p 1433:1433 \
  -e SA_PASSWORD="YourStrong@Passw0rd123" \
  --name my-sql-container \
  my-app-db:v1.0.0
```

**Connection Details:**
- **Server**: `localhost,1433`
- **Authentication**: SQL Login
- **User**: `sa`
- **Password**: `YourStrong@Passw0rd123` (or your custom password)
- **Database**: `ImportedDatabase` (or your custom database name)

### Example Migration Script

```sql
-- 001-add-user-table.sql
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Users')
BEGIN
    CREATE TABLE Users (
        Id int IDENTITY(1,1) PRIMARY KEY,
        Username nvarchar(50) NOT NULL UNIQUE,
        Email nvarchar(100) NOT NULL,
        CreatedDate datetime2 DEFAULT GETUTCDATE()
    );
    PRINT 'Created Users table';
END
ELSE
BEGIN
    PRINT 'Users table already exists';
END
```

## 🐛 Troubleshooting

### Common Issues

1. **Azure CLI not authenticated**
   ```bash
   az login
   ```

2. **Docker daemon not running**
   ```bash
   # Windows/macOS: Start Docker Desktop
   # Linux: sudo systemctl start docker
   ```

3. **PowerShell execution policy**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

4. **Missing Azure permissions**
   - SQL Database: `db_owner` role (for export)
   - Storage Account: `Storage Blob Data Contributor` role
   - Container Registry: `AcrPush` role

### Logging

All scripts support configurable logging levels:

```powershell
# Enable debug logging
.\build.ps1 -LogLevel "Debug" [other parameters...]

# Error-only logging
.\build.ps1 -LogLevel "Error" [other parameters...]
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes following PowerShell best practices
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:

1. Check the [examples](examples/usage-examples.md) for common scenarios
2. Review the troubleshooting section above
3. Check the logs with debug level enabled
4. Open an issue with detailed error information

## 🎯 Roadmap

- [ ] Multi-database parallel processing
- [ ] Container rollback capabilities
- [ ] Performance optimization for large databases
- [ ] Advanced validation and testing
- [ ] Template library for common patterns
- [ ] Integration with monitoring systems
