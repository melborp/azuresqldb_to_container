# BACPAC to Container Toolkit

A **portable automation toolkit** for exporting Azure SQL Databases to BACPAC format and importing them into containerized SQL Server instances with migration script execution.

## 🚀 Core Purpose

1. **Export** Azure SQL Database to BACPAC format
2. **Import** BACPAC into SQL Server container during Docker build
3. **Execute** migration scripts during container startup
4. **Publish** to Azure Container Registry

**Key Benefits**: Parameter-driven execution • CI/CD ready • Cross-platform • Fail-fast validation • Optimized container images

## ⚡ Quick Start

### Prerequisites
- PowerShell 7.x+ 
- Docker
- Azure CLI (`az login`)
- SqlPackage utility

### Complete Workflow
```powershell
# Export database → Build container → Push to registry
.\build.ps1 `
    -SubscriptionId "your-subscription-id" `
    -ResourceGroupName "my-rg" `
    -ServerName "my-sql-server" `
    -DatabaseName "MyDatabase" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BacpacFileName "database.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -RegistryName "myregistry" `
    -MigrationScriptPaths @("migrations/*.sql")
```

### Build from Existing BACPAC
```powershell
# Skip export, build from existing BACPAC
.\build.ps1 `
    -BacpacPath "https://storage.blob.core.windows.net/bacpacs/database.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -SkipExport `
    -MigrationScriptPaths @("migrations/*.sql")
```

## 🔧 Modular Scripts

The toolkit provides **modular components** for advanced scenarios and custom workflows:

| Script | Purpose | Input → Output |
|--------|---------|----------------|
| [`Export-AzureSqlDatabase.ps1`](docs/Modular-Scripts.md#export-azuresqldatabaseps1) | Database export with AccessToken auth | Azure SQL DB → Local BACPAC |
| [`Upload-FileToBlobStorage.ps1`](docs/Modular-Scripts.md#upload-filetoblobstorageps1) | Generic file upload to Azure Storage | Local File → Blob Storage |
| [`Download-FileFromBlobStorage.ps1`](docs/Modular-Scripts.md#download-filefromblobstorageps1) | Download with multiple auth fallbacks | Blob Storage → Local File |
| [`Build-SqlServerImage.ps1`](docs/Modular-Scripts.md#build-sqlserverimages1) | Multi-database Docker image builder | Multiple BACPAC → Docker Image |

### Advanced Multi-Database Example
```powershell
# Download multiple BACPAC files
.\scripts\Download-FileFromBlobStorage.ps1 -BlobUrl "https://storage.../app.bacpac" -LocalPath "app.bacpac"
.\scripts\Download-FileFromBlobStorage.ps1 -BlobUrl "https://storage.../config.bacpac" -LocalPath "config.bacpac"

# Build image with multiple databases
$securePassword = ConvertTo-SecureString "MyPassword123!" -AsPlainText -Force
.\scripts\Build-SqlServerImage.ps1 `
    -ImageName "multi-db-app" `
    -ImageTag "v2.0.0" `
    -BacpacPaths @("app.bacpac", "config.bacpac") `
    -DatabaseNames @("AppDatabase", "ConfigDatabase") `
    -MigrationScriptPaths @("migrations/*.sql") `
    -SqlServerPassword $securePassword

# Run with mounted migration scripts
docker run -d -p 1433:1433 \
  -e SA_PASSWORD='MyPassword123!' \
  -v ./runtime-migrations:/var/opt/mssql/migration-scripts \
  multi-db-app:v2.0.0
```

📖 **[Complete Modular Scripts Documentation →](docs/Modular-Scripts.md)**

## 📦 Legacy Script (Deprecated)

The original `Build-SqlContainer.ps1` script has been **split into modular components** for better maintainability and flexibility. It still works but shows deprecation warnings:

**Legacy Usage (Still Supported):**
```powershell
# Original monolithic approach
.\scripts\Build-SqlContainer.ps1 `
    -BacpacPath "https://storage.blob.core.windows.net/bacpacs/database.bacpac" `
    -ImageName "my-app" `
    -ImageTag "v1.0.0" `
    -MigrationScriptPaths @("migrations/*.sql")
```

**⚠️ Migration Path:** Use the new modular scripts for new projects:
1. [`Download-FileFromBlobStorage.ps1`](docs/Modular-Scripts.md#download-filefromblobstorageps1) - For downloading BACPAC files
2. [`Build-SqlServerImage.ps1`](docs/Modular-Scripts.md#build-sqlserverimages1) - For building multi-database images

## 🔄 Migration Workflows

**Split functionality for enhanced flexibility:**

```powershell
# 1. Export database to local file
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId $subId `
    -ServerName "myserver" `
    -DatabaseName "MyDatabase" `
    -OutputPath "C:\temp\database.bacpac"

# 2. Upload file to blob storage  
.\scripts\Upload-FileToBlobStorage.ps1 `
    -SubscriptionId $subId `
    -FilePath "C:\temp\database.bacpac" `
    -StorageAccountName "storage" `
    -ContainerName "bacpacs" `
    -Overwrite
```

**Benefits**: Export multiple databases • Upload to different storage accounts • Parallel processing • Generic file uploads

## 🏗️ Architecture

```
Azure SQL Database → BACPAC → Blob Storage → Docker Build → Container Registry
                                                    ↓
                            Migration Scripts → Container Runtime
```

**Multi-Stage Build Process**:
1. **Stage 1**: Import BACPAC into SQL Server
2. **Stage 2**: Copy database files to final image (BACPAC excluded)
3. **Runtime**: Execute migration scripts during container startup

## 🔐 Required Permissions

### Azure SQL Database
```sql
-- Grant export permissions to your Azure AD account
ALTER ROLE db_owner ADD MEMBER [your-email@domain.com];
```

### Azure Storage & Registry
- **Storage Blob Data Contributor** (for blob storage)
- **AcrPush** (for container registry)

### Authentication
- **Development**: `az login`
- **CI/CD**: Service principal authentication
- **Database**: Azure AD AccessToken authentication (no SQL credentials needed)

## 📋 CI/CD Integration

### Azure DevOps
```yaml
- task: PowerShell@2
  inputs:
    filePath: 'build.ps1'
    arguments: |
      -SubscriptionId $(AZURE_SUBSCRIPTION_ID)
      -ResourceGroupName $(RESOURCE_GROUP_NAME)
      -ServerName $(SQL_SERVER_NAME)
      -DatabaseName $(DATABASE_NAME)
      -StorageAccountName $(STORAGE_ACCOUNT_NAME)
      -ContainerName "bacpacs"
      -ImageName $(IMAGE_NAME)
      -ImageTag $(Build.BuildNumber)
      -RegistryName $(REGISTRY_NAME)
```

### GitHub Actions
```yaml
- name: Build Database Container
  shell: pwsh
  run: |
    .\build.ps1 `
      -SubscriptionId "${{ secrets.AZURE_SUBSCRIPTION_ID }}" `
      -ServerName "${{ secrets.SQL_SERVER_NAME }}" `
      -DatabaseName "${{ secrets.DATABASE_NAME }}" `
      -StorageAccountName "${{ secrets.STORAGE_ACCOUNT_NAME }}" `
      -ImageName "my-app" `
      -ImageTag "${{ github.run_number }}"
```

## 📝 Migration Scripts

Scripts run during **container startup** and should be:
- **Idempotent** (safe to run multiple times)
- **Fast** (container startup dependency)
- **Ordered** (alphabetical execution)
- **Validated** (any failure stops container)

```sql
-- Example: 001-add-users-table.sql
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Users')
BEGIN
    CREATE TABLE Users (
        Id int IDENTITY(1,1) PRIMARY KEY,
        Username nvarchar(50) NOT NULL
    );
    PRINT 'Created Users table';
END
```

## 📁 Project Structure

```
├── scripts/
│   ├── Export-AzureSqlDatabase.ps1    # Database export (AccessToken auth)
│   ├── Upload-FileToBlobStorage.ps1   # Generic file upload
│   ├── Build-SqlContainer.ps1         # Container build
│   └── Push-ContainerImage.ps1        # Registry push
├── docker/
│   ├── Dockerfile                     # Multi-stage build
│   └── entrypoint.sh                  # Migration script execution
├── build.ps1                         # Main orchestrator
└── docs/                             # Detailed documentation
```

## 🐛 Troubleshooting

**Common Issues**:
- Azure CLI not authenticated: `az login`
- Docker not running: Start Docker Desktop
- Missing permissions: Check Azure RBAC roles
- PowerShell execution policy: `Set-ExecutionPolicy RemoteSigned`

**Debug Logging**:
```powershell
.\build.ps1 -LogLevel "Debug" [parameters...]
```

## 📚 Documentation

- **[Detailed Examples](examples/usage-examples.md)** - Comprehensive usage scenarios
- **[Modular Scripts Guide](docs/Modular-Scripts.md)** - New split script documentation  
- **[Permission Setup](docs/Required-Permissions.md)** - Azure RBAC configuration
- **[CI/CD Authentication](docs/CI-CD-Authentication.md)** - Service principal setup
- **[SqlPackage Installation](docs/SqlPackage-Installation.md)** - Links to official Microsoft documentation

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.
