# SqlPackage Installation

The BACPAC to Container toolkit uses **SqlPackage utility** for database export operations. SqlPackage provides better Azure AD authentication support compared to Azure CLI's database export commands.

## Installation

For the latest installation instructions, please refer to Microsoft's official documentation:

**📖 [SqlPackage Download and Installation Guide](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download)**

The official guide covers:
- Download links for Windows, macOS, and Linux
- .NET tool installation (`dotnet tool install -g microsoft.sqlpackage`)
- Installation via SQL Server Data Tools (SSDT)
- PATH configuration
- Version verification

## Quick Verification

After installation, verify SqlPackage is available:
```powershell
sqlpackage /version
```

## Why SqlPackage?

| Feature | SqlPackage | Azure CLI (`az sql db export`) |
|---------|------------|--------------------------------|
| Azure AD Authentication | ✅ Full support | ❌ Not supported |
| SQL Authentication | ✅ Supported | ✅ Required |
| Direct export to file | ✅ Yes | ❌ Must go through Azure Storage |
| Performance | ✅ Better | ❌ Slower (Azure service) |
| Large database support | ✅ Better handling | ❌ Size limitations |

## Troubleshooting

For installation and configuration issues, please refer to:
- **[Official SqlPackage Documentation](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/)**
- **[SqlPackage Release Notes](https://learn.microsoft.com/en-us/sql/tools/release-notes-sqlpackage)**

**Common Issues**:
- **"SqlPackage not found"**: Ensure it's in PATH or restart terminal after installation
- **Authentication failed**: Verify Azure login (`az login`) and database permissions
- **Connection failed**: Check server name format and firewall rules
