# Project Overview
This project provides a **portable automation toolkit** for Azure SQL Database containerization that:
1. Exports Azure SQL Database to BACPAC format and uploads to Azure Blob Storage
2. Downloads BACPAC and imports into a SQL Server container
3. Executes externally-provided migration and upgrade SQL scripts during container build
4. Validates all script executions - container build fails if any script fails
5. Publishes the built container image to Azure Container Registry with specified name and tag

The solution uses cross-platform PowerShell (PowerShell Core) scripts designed for **CI/CD integration** and **parameter-driven execution**.

## Key Design Principles
- **Parameter-Driven**: All configuration via script parameters or environment variables
- **CI/CD Agnostic**: Works with any CI/CD system (Azure DevOps, GitHub Actions, Jenkins, etc.)
- **External Script Support**: Migration/upgrade scripts are provided externally, not stored in this repo
- **Fail-Fast**: Any SQL script failure immediately fails the container build
- **Portable**: No environment-specific configurations or internal state management

## Architecture
```
External CI/CD Pipeline
    ↓ (provides parameters & SQL scripts)
PowerShell Scripts
    ↓ (orchestrates)
Azure Services + Docker
    ↓ (produces)
Containerized Database
```

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

# Future Iterations
## Planned Enhancements
- **Multi-database support**: Process multiple databases in parallel
- **Rollback capabilities**: Container versioning and rollback mechanisms
- **Performance optimization**: Parallel script execution where safe
- **Advanced validation**: Schema comparison and data integrity checks
- **Monitoring integration**: Health checks and telemetry collection
- **Template library**: Common migration pattern templates

## Extensibility Points
- **Custom script runners**: Support for different SQL execution engines
- **Plugin architecture**: Custom validation and transformation steps
- **Container customization**: Flexible base image and configuration options
- **Integration adapters**: Specific CI/CD platform optimizations
