# Modular Architecture Changes Summary

## Overview
The `Build-SqlContainer.ps1` script has been successfully split into two focused components for better maintainability, flexibility, and reusability.

## New Modular Scripts

### 1. Download-FileFromBlobStorage.ps1
**Purpose**: Downloads files from Azure Blob Storage using Azure CLI authentication

**Key Features**:
- ✅ Multiple authentication fallback methods (Azure CLI → Storage Key → SAS Token)
- ✅ Automatic file verification with integrity checking
- ✅ Support for BACPAC and SQL file validation
- ✅ Progress reporting and detailed logging
- ✅ Force overwrite capability

**Usage**:
```powershell
.\scripts\Download-FileFromBlobStorage.ps1 `
    -BlobUrl "https://storage.blob.core.windows.net/container/file.bacpac" `
    -LocalPath "C:\temp\file.bacpac" `
    -Force `
    -VerifyIntegrity
```

### 2. Build-SqlServerImage.ps1
**Purpose**: Builds Docker images with multiple BACPAC files and migration script support

**Key Features**:
- ✅ **Multiple BACPAC Support**: Import multiple databases in one image
- ✅ **Build-Time Import**: BACPAC files imported during build (not in final image)
- ✅ **Runtime Migration Scripts**: Scripts mounted as volumes and executed at startup
- ✅ **Multi-Stage Docker Build**: Optimized image size with separate build/runtime stages
- ✅ **Automatic Database Naming**: Smart naming from filenames or custom names
- ✅ **SecureString Password**: Proper security for sensitive parameters
- ✅ **Manifest Generation**: Build documentation and usage instructions

**Usage**:
```powershell
$securePassword = ConvertTo-SecureString "MyPassword123!" -AsPlainText -Force

.\scripts\Build-SqlServerImage.ps1 `
    -ImageName "my-app" `
    -ImageTag "v1.0.0" `
    -BacpacPaths @("app.bacpac", "config.bacpac") `
    -DatabaseNames @("AppDatabase", "ConfigDatabase") `
    -MigrationScriptPaths @("migrations/*.sql") `
    -SqlServerPassword $securePassword
```

## Architecture Benefits

### Before (Monolithic)
- Single script handling download + build
- Limited to one BACPAC file per image
- BACPAC files included in final image
- Migration scripts embedded in image
- Less flexibility for complex scenarios

### After (Modular)
- **Separation of Concerns**: Download and build are separate operations
- **Multiple Database Support**: One image can contain multiple imported databases
- **Optimized Image Size**: BACPAC files imported during build, not stored in final image
- **Runtime Flexibility**: Migration scripts mounted as volumes for easy updates
- **Enhanced Security**: SecureString for passwords, proper authentication fallbacks
- **CI/CD Friendly**: Individual components can be used in custom workflows

## Docker Image Architecture

### Multi-Stage Build Process
```dockerfile
# Stage 1: Import BACPAC files
FROM mcr.microsoft.com/mssql/server:2022-latest AS importer
# - Installs SqlPackage
# - Imports all BACPAC files during build
# - Creates databases with proper names

# Stage 2: Runtime image  
FROM mcr.microsoft.com/mssql/server:2022-latest
# - Copies imported databases from Stage 1
# - Sets up migration script execution at startup
# - Minimal final image size
```

### Container Startup Process
1. **SQL Server Start**: Starts SQL Server with imported databases
2. **Migration Detection**: Checks for mounted migration scripts
3. **Script Execution**: Runs .sql files in alphabetical order
4. **Ready State**: Container ready for connections

## Migration Script Support

### Build-Time vs Runtime
- **Build-Time**: BACPAC files imported during Docker build (permanent)
- **Runtime**: Migration scripts executed when container starts (flexible)

### Script Mounting
```bash
docker run -d -p 1433:1433 \
  -e SA_PASSWORD='MyPassword123!' \
  -v ./migration-scripts:/var/opt/mssql/migration-scripts:ro \
  my-app:v1.0.0
```

### Script Naming Convention
```
migration-scripts/
├── 001_create_indexes.sql
├── 002_update_schema.sql  
├── 003_seed_data.sql
```

## Legacy Support

### Build-SqlContainer.ps1 (Deprecated)
- ✅ Still functional with deprecation warnings
- ✅ Provides migration path information
- ✅ Recommends new modular scripts
- ⚠️ Will be maintained but not enhanced

## Documentation Updates

### New Documentation
- **[Modular-Scripts.md](docs/Modular-Scripts.md)**: Comprehensive guide for all modular scripts
- **[multi-database-container.md](examples/multi-database-container.md)**: Complete example workflow
- **Updated README.md**: Integration with modular approach

### Key Sections Added
- Complete workflow examples
- CI/CD pipeline integration
- Migration script best practices
- Troubleshooting guide
- Docker Compose and Kubernetes examples

## Example Workflows

### Complete Database-to-Container Workflow
```powershell
# 1. Export database
.\scripts\Export-AzureSqlDatabase.ps1 -SubscriptionId $sub -ServerName "server" -DatabaseName "db" -OutputPath "db.bacpac"

# 2. Upload to storage (optional)
.\scripts\Upload-FileToBlobStorage.ps1 -FilePath "db.bacpac" -StorageAccountName "storage" -ContainerName "bacpacs"

# 3. Download BACPAC files (if from storage)
.\scripts\Download-FileFromBlobStorage.ps1 -BlobUrl "https://storage.../db.bacpac" -LocalPath "db.bacpac"

# 4. Build Docker image
.\scripts\Build-SqlServerImage.ps1 -ImageName "app" -ImageTag "v1.0" -BacpacPaths @("db.bacpac")

# 5. Run container with migration scripts
docker run -d -p 1433:1433 -e SA_PASSWORD='pwd' -v ./migrations:/var/opt/mssql/migration-scripts app:v1.0
```

### Multi-Database Scenario
```powershell
# Build image with multiple databases
.\scripts\Build-SqlServerImage.ps1 `
    -ImageName "multi-db-app" `
    -ImageTag "v2.0.0" `
    -BacpacPaths @("app.bacpac", "config.bacpac", "logging.bacpac") `
    -DatabaseNames @("AppDatabase", "ConfigDatabase", "LoggingDatabase") `
    -MigrationScriptPaths @("migrations/*.sql")
```

## Testing and Validation

### Script Validation
- ✅ PowerShell syntax validation passed
- ✅ Security analysis passed (SecureString usage)
- ✅ Help documentation generated correctly
- ✅ Parameter validation implemented

### Container Testing
- ✅ Multi-stage build optimization
- ✅ BACPAC import during build
- ✅ Migration script execution at runtime
- ✅ Image size optimization verified

## Migration Recommendations

### For New Projects
- Use `Download-FileFromBlobStorage.ps1` + `Build-SqlServerImage.ps1`
- Leverage multi-database capabilities for complex applications
- Mount migration scripts as volumes for flexibility

### For Existing Projects
- Legacy `Build-SqlContainer.ps1` continues to work
- Gradual migration to modular scripts recommended
- Follow deprecation warnings for guidance

### For CI/CD Pipelines
- Update pipeline definitions to use modular scripts
- Take advantage of individual script flexibility
- Implement proper error handling for each stage

## Benefits Summary

✅ **Better Separation of Concerns**: Each script has a single, focused responsibility
✅ **Enhanced Flexibility**: Multiple databases, runtime script mounting
✅ **Improved Security**: SecureString passwords, multiple auth methods
✅ **Optimized Performance**: Smaller final images, faster builds
✅ **Better Maintainability**: Modular code is easier to test and update
✅ **CI/CD Ready**: Individual components work well in automated pipelines
✅ **Future-Proof**: Architecture supports advanced scenarios and extensions
