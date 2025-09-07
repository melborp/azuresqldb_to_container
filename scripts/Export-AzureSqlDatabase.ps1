# Export-AzureSqlDatabase.ps1
# Exports an Azure SQL Database to BACPAC format using SqlPackage utility with AccessToken authentication
#
# This script uses SqlPackage utility for database export with Azure AD authentication via access tokens.
# This approach is recommended for CI/CD environments and provides better security.
#
# Prerequisites:
# - SqlPackage utility must be installed and available in PATH
# - Azure CLI for authentication (az login must be executed)
# - Valid access token for https://database.windows.net/ resource scope
# - Appropriate permissions for the database (db_datareader, db_datawriter, db_ddladmin, or db_owner)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure subscription ID")]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true, HelpMessage = "SQL server name (FQDN or short name)")]
    [string]$ServerName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Database name to export")]
    [string]$DatabaseName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Output path for BACPAC file")]
    [string]$OutputPath,
    
    [Parameter(Mandatory = $false, HelpMessage = "Azure AD tenant ID (optional, will be auto-detected if not provided)")]
    [string]$TenantId,
    
    [Parameter(Mandatory = $false, HelpMessage = "Log level (Debug, Info, Warning, Error, Critical)")]
    [ValidateSet("Debug", "Info", "Warning", "Error", "Critical")]
    [string]$LogLevel = "Info"
)

# Import helper modules
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptDir\common\Logging-Helpers.ps1"
. "$scriptDir\common\Azure-Helpers.ps1"

# Configure logging
Set-LogLevel $LogLevel
Set-LogPrefix "EXPORT-DB"

function main {
    try {
        Write-InfoLog "=== Azure SQL Database Export Started ===" @{
            SubscriptionId = $SubscriptionId
            Server = $ServerName
            Database = $DatabaseName
            OutputPath = $OutputPath
            AuthMethod = "Azure AD AccessToken"
        }
        
        # Validate prerequisites
        Write-InfoLog "Validating prerequisites..."
        
        if (-not (Test-AzureConnection)) {
            Write-CriticalLog "Azure connection validation failed"
        }
        
        # Set subscription
        Set-AzureSubscription -SubscriptionId $SubscriptionId
        
        # Validate output path
        $outputDir = Split-Path -Parent $OutputPath
        if ($outputDir -and -not (Test-Path $outputDir)) {
            Write-InfoLog "Creating output directory: $outputDir"
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # Ensure .bacpac extension
        if (-not $OutputPath.EndsWith(".bacpac")) {
            $OutputPath = $OutputPath + ".bacpac"
            Write-InfoLog "Added .bacpac extension to output path: $OutputPath"
        }
        
        # Check if output file already exists
        if (Test-Path $OutputPath) {
            Write-WarningLog "Output file already exists and will be overwritten: $OutputPath"
        }
        
        # Check if SqlPackage is available
        Write-InfoLog "Checking SqlPackage availability..."
        try {
            $sqlPackageVersion = & sqlpackage /version 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-CriticalLog "SqlPackage utility not found or returned error"
            }
            Write-InfoLog "SqlPackage found: $sqlPackageVersion"
        }
        catch {
            Write-CriticalLog "SqlPackage utility not found. Please install SqlPackage from https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download"
        }
        
        # Build connection string
        $serverFqdn = if ($ServerName.Contains('.')) { $ServerName } else { "$ServerName.database.windows.net" }
        $connectionString = "Data Source=$serverFqdn;Initial Catalog=$DatabaseName;"
        
        Write-InfoLog "Preparing database export..." @{
            ServerFqdn = $serverFqdn
            DatabaseName = $DatabaseName
            OutputPath = $OutputPath
        }
        
        # Get SQL Database access token
        Write-InfoLog "Getting SQL Database access token..."
        $accessToken = az account get-access-token --resource "https://database.windows.net/" --query "accessToken" -o tsv 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $accessToken) {
            Write-CriticalLog "Failed to get SQL Database access token. Ensure Azure CLI is authenticated with 'az login' and has access to the database resource scope."
        }
        
        Write-InfoLog "Access token acquired successfully - assuming token is valid for database access"
        
        # Get tenant ID if not provided
        if (-not $TenantId) {
            Write-InfoLog "Detecting Azure AD tenant ID..."
            $tenantInfo = az account show --query "tenantId" -o tsv 2>$null
            if ($LASTEXITCODE -eq 0 -and $tenantInfo) {
                $TenantId = $tenantInfo.Trim()
                Write-InfoLog "Detected tenant ID: $TenantId"
            }
        }
        
        # Build SqlPackage arguments
        $sqlPackageArgs = @(
            "/Action:Export"
            "/TargetFile:$OutputPath"
            "/SourceConnectionString:$connectionString"
            "/AccessToken:$accessToken"
            "/ua:True"
        )
        
        # Add tenant ID if available
        if ($TenantId) {
            $sqlPackageArgs += "/TenantId:$TenantId"
        }
        
        # Execute SqlPackage export
        Write-InfoLog "Executing SqlPackage export..."
        
        # Debug: Show actual parameters (excluding sensitive data)
        $debugArgs = $sqlPackageArgs | ForEach-Object { 
            if ($_ -like "/AccessToken:*") { 
                "/AccessToken:[REDACTED]" 
            } else { 
                $_ 
            } 
        }
        Write-InfoLog "SqlPackage parameters: $($debugArgs -join ' ')"
        
        $exportResult = & sqlpackage @sqlPackageArgs 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog "SqlPackage export output: $exportResult"
            Write-CriticalLog "SqlPackage export failed with exit code: $LASTEXITCODE"
        }
        
        # Verify BACPAC file was created
        if (-not (Test-Path $OutputPath)) {
            Write-CriticalLog "BACPAC file was not created at expected location: $OutputPath"
        }
        
        $fileInfo = Get-Item $OutputPath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        
        Write-InfoLog "=== Azure SQL Database Export Completed Successfully ===" @{
            OutputPath = $OutputPath
            FileSizeMB = $fileSizeMB
            CreatedTime = $fileInfo.CreationTime
        }
        
        # Output key information for automation
        Write-Host "##[section]Export Results"
        Write-Host "BACPAC_PATH=$OutputPath"
        Write-Host "BACPAC_FILENAME=$($fileInfo.Name)"
        Write-Host "BACPAC_SIZE_MB=$fileSizeMB"
        Write-Host "BACPAC_SIZE_BYTES=$($fileInfo.Length)"
        
        exit 0
    }
    catch {
        Write-CriticalLog "Unhandled error in database export: $($_.Exception.Message)"
        exit 1
    }
}

# Execute main function
main
