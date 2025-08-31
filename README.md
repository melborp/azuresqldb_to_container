# BACPAC to Container Toolkit

A comprehensive PowerShell-based automation toolkit for exporting Azure SQL Databases to BACPAC format, importing them into SQL Server containers, executing migration scripts, and publishing to Azure Container Registry.

## 🚀 Features

- **Azure SQL Database Export**: Export databases to BACPAC format with Azure Blob Storage integration
- **Build-Time Database Import**: Import BACPAC during Docker build process for optimized final image
- **Migration Script Execution**: Run custom migration and upgrade scripts during container startup
- **Optimized Image Size**: Final container excludes BACPAC file, containing only the imported database
- **Fail-Fast Validation**: Container build fails if BACPAC import fails; runtime fails if any script fails
- **CI/CD Ready**: Parameter-driven scripts designed for pipeline integration
- **Cross-Platform**: PowerShell Core compatible (Windows, Linux, macOS)
- **Comprehensive Logging**: Structured logging with configurable levels
- **Azure Container Registry**: Automated image tagging and publishing

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
│  External SQL   │                           │ Docker Build    │
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
3. **Runtime**: Execute only migration/upgrade scripts on container startup

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
   
   # Check Docker
   docker --version
   ```

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
    -MigrationScriptPaths @("path\to\migration1.sql", "path\to\migration2.sql") `
    -UpgradeScriptPaths @("path\to\upgrade.sql")
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
│   ├── Export-AzureSqlDatabase.ps1    # Azure SQL Database export
│   ├── Build-SqlContainer.ps1         # Container build with BACPAC import
│   ├── Push-ContainerImage.ps1        # Azure Container Registry push
│   └── common/
│       ├── Logging-Helpers.ps1        # Structured logging utilities
│       ├── Azure-Helpers.ps1          # Azure-specific functions
│       └── Docker-Helpers.ps1         # Docker management functions
├── docker/
│   ├── Dockerfile                     # Multi-stage SQL Server container
│   ├── import-bacpac.sh               # BACPAC import during build stage
│   ├── entrypoint.sh                  # Container startup script (migration/upgrade only)
│   └── wait-for-sqlserver.sh          # SQL Server readiness check
├── examples/
│   ├── sample-migration.sql           # Example migration script
│   ├── usage-examples.md             # Comprehensive usage examples
│   └── sample-ci-pipeline.yml        # CI/CD pipeline examples
├── build.ps1                         # Main orchestrator script
├── Agents.md                         # Project requirements and design
├── README.md                         # This file
└── .gitignore                        # Git ignore patterns
```

## 🔧 Individual Script Usage

### 1. Export Azure SQL Database

```powershell
.\scripts\Export-AzureSqlDatabase.ps1 `
    -SubscriptionId "your-subscription-id" `
    -ResourceGroupName "my-rg" `
    -ServerName "my-sql-server" `
    -DatabaseName "MyDatabase" `
    -StorageAccountName "mystorageaccount" `
    -ContainerName "bacpacs" `
    -BacpacFileName "database.bacpac"
```

### 2. Build SQL Container

```powershell
.\scripts\Build-SqlContainer.ps1 `
    -BacpacPath "path\to\database.bacpac" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -MigrationScriptPaths @("script1.sql", "script2.sql") `
    -UpgradeScriptPaths @("upgrade.sql")
```

### 3. Push to Azure Container Registry

```powershell
.\scripts\Push-ContainerImage.ps1 `
    -RegistryName "myregistry" `
    -ImageName "my-app-db" `
    -ImageTag "v1.0.0" `
    -AdditionalTags @("latest", "stable")
```

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
      -UpgradeScriptPaths $(UPGRADE_SCRIPTS)
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
| `UpgradeScriptPaths` | No | Array of upgrade script paths |
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

Migration and upgrade scripts run during **container startup** (not during build) and should follow these guidelines:

1. **Idempotent**: Safe to run multiple times
2. **Transactional**: Use transactions where appropriate
3. **Validated**: Test thoroughly before use
4. **Ordered**: Use naming conventions for execution order (scripts are executed alphabetically)
5. **Logged**: Include PRINT statements for debugging
6. **Fast Execution**: Keep scripts lightweight as they run during container startup

### Script Execution Order

1. **Build Time**: BACPAC import (automatic, no custom scripts)
2. **Runtime**: Migration scripts (executed first during container startup)
3. **Runtime**: Upgrade scripts (executed after migration scripts)

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
   - SQL Database Contributor (for export)
   - Storage Blob Data Contributor (for BACPAC storage)
   - AcrPush (for container registry)

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
