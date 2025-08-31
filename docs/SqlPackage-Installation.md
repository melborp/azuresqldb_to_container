# SqlPackage Installation Guide

The BACPAC to Container toolkit uses **SqlPackage utility** for database export operations. SqlPackage provides better Azure AD authentication support compared to Azure CLI's database export commands.

## Installation Options

### Option 1: Download SqlPackage Standalone
Download the latest version from Microsoft:
- **Windows**: https://go.microsoft.com/fwlink/?linkid=2196334
- **macOS**: https://go.microsoft.com/fwlink/?linkid=2196335  
- **Linux**: https://go.microsoft.com/fwlink/?linkid=2196336

### Option 2: Install via .NET Tool (Recommended)
```bash
dotnet tool install -g microsoft.sqlpackage
```

### Option 3: Visual Studio/SSDT Installation
SqlPackage is included with:
- SQL Server Data Tools (SSDT)
- SQL Server Management Studio (SSMS)
- Visual Studio with SQL Server workload

## Verification

After installation, verify SqlPackage is available:
```powershell
sqlpackage /version
```

You should see output like:
```
sqlpackage version 162.0.52.1
```

## PATH Configuration

Ensure SqlPackage is in your system PATH, or the script will fail with:
```
SqlPackage utility not found. Please install SqlPackage from https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download
```

### Windows PATH Setup
If SqlPackage is installed but not in PATH, add it manually:
1. Find SqlPackage.exe location (typically in Program Files)
2. Add the folder to your system PATH environment variable
3. Restart PowerShell/Command Prompt

### Alternative: Specify Full Path
You can modify the script to use a specific SqlPackage path instead of relying on PATH.

## Azure AD Authentication Requirements

For Azure AD authentication to work with SqlPackage:

1. **User must be authenticated** with Azure AD (via `az login` or similar)
2. **User must have access** to the target Azure SQL Database
3. **Azure AD authentication must be enabled** on the Azure SQL Server
4. **Tenant ID** may need to be specified explicitly in some environments

## Benefits of SqlPackage vs Azure CLI

| Feature | SqlPackage | Azure CLI (`az sql db export`) |
|---------|------------|--------------------------------|
| Azure AD Authentication | ✅ Full support | ❌ Not supported |
| SQL Authentication | ✅ Supported | ✅ Required |
| Direct export to file | ✅ Yes | ❌ Must go through Azure Storage |
| Performance | ✅ Better | ❌ Slower (Azure service) |
| Offline capability | ✅ Local export | ❌ Requires Azure service |
| Large database support | ✅ Better handling | ❌ Size limitations |

## Troubleshooting

### "SqlPackage not found"
- Ensure SqlPackage is installed
- Verify it's in PATH or specify full path
- Restart terminal after installation

### "Authentication failed"
- Ensure you're logged in to Azure (`az login`)
- Verify Azure AD permissions on the database
- Try specifying TenantId explicitly

### "Connection failed"
- Check server name formatting (should include .database.windows.net)
- Verify firewall rules allow your IP
- Confirm database exists and is accessible

### "Export operation failed"
- Check available disk space for temporary file
- Verify storage account permissions
- Monitor SqlPackage output for specific errors
