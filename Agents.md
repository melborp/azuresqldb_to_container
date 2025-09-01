# Project Overview
This project provides a **portable automation toolkit** for Azure SQL Database containerization that:
1. Exports Azure SQL Database to BACPAC format and uploads to Azure Blob Storage
2. Downloads BACPAC and imports into a SQL Server container during Docker build
3. Executes externally-provided migration SQL scripts during container startup
4. Validates all script executions - container build fails if any script fails
5. Publishes the built container image to Azure Container Registry with specified name and tag

The solution uses cross-platform PowerShell (PowerShell Core) scripts designed for **CI/CD integration** and **parameter-driven execution**.

## Key Design Principles
- **Parameter-Driven**: All configuration via script parameters or environment variables
- **CI/CD Agnostic**: Works with any CI/CD system (Azure DevOps, GitHub Actions, Jenkins, etc.)
- **External Script Support**: Migration scripts are provided externally, not stored in this repo
- **Fail-Fast**: Any SQL script failure immediately fails the container build or startup
- **Portable**: No environment-specific configurations or internal state management
- **Simplified Architecture**: Single migration script directory for easier management
- **Optimized Images**: Multi-stage Docker builds exclude BACPAC from final image

## Architecture
```
External CI/CD Pipeline
    ↓ (provides parameters & SQL scripts)
PowerShell Scripts
    ↓ (orchestrates)
Azure Services + Docker Multi-Stage Build
    ↓ (produces)
Containerized Database (BACPAC excluded)
```

## Current Implementation Status
- **✅ PowerShell Core Scripts**: Cross-platform automation with comprehensive error handling
- **✅ Azure Integration**: Azure AD authentication, Blob Storage, Container Registry
- **✅ Multi-Stage Docker Build**: BACPAC imported during build, excluded from final image
- **✅ Migration Scripts**: Executed during container startup with fail-fast validation
- **✅ Simplified Architecture**: Removed upgrade script complexity, single migration directory
- **✅ CI/CD Ready**: Parameter-driven execution with structured logging
- **✅ Container Management**: Proper SQL Server lifecycle management with simplified entrypoint

# Required Permissions

## Azure SQL Database
To export a database, your Azure AD account needs these database-level permissions:

```sql
-- Replace 'your-email@domain.com' with your actual Azure AD email
CREATE USER [your-email@domain.com] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [your-email@domain.com];
ALTER ROLE db_datawriter ADD MEMBER [your-email@domain.com];
ALTER ROLE db_owner ADD MEMBER [your-email@domain.com]; -- For export operations
```

## Azure Blob Storage
Your Azure AD account needs **Storage Blob Data Contributor** role on the storage account or container.

## Azure Container Registry
For pushing images: **AcrPush** role on the container registry.

# Setup
- Cross-platform PowerShell Core (7.x+) required
- Docker Desktop or Docker Engine
- Azure CLI for authentication
- Git repository for version control

# Build & Test
- All scripts include parameter validation and comprehensive error handling
- Each script returns appropriate exit codes for CI/CD integration
- Container builds include health checks and validation steps
- Logging output formatted for CI/CD pipeline consumption

# Code Style
- Use clear naming and standard PowerShell code style
- Follow PowerShell approved verbs (Get-, Set-, New-, etc.)
- Comprehensive parameter validation with meaningful error messages
- Structured logging with severity levels
- Modular design with reusable helper functions

# Security Considerations
- **Never commit secrets**: No `.env` files, connection strings, or passwords in code
- **Parameter-based security**: All sensitive data passed as parameters or environment variables
- **Audit logging**: All operations logged for security compliance
- **Least privilege**: Scripts request only necessary permissions
- **Credential isolation**: External credential management (Azure Key Vault, CI/CD secrets)


