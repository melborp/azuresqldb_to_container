# Export-AzureSqlDatabase.ps1
# Exports an Azure SQL Database to BACPAC format and uploads to Azure Blob Storage
#
# IMPORTANT: This script requires SQL Server admin credentials (-AdminUser and -AdminPassword)
# because Azure CLI's 'az sql db export' command does not support Azure AD authentication.
# While the script uses Azure AD for Azure resource management (storage, etc.), 
# SQL authentication is required specifically for the database export operation.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure subscription ID")]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true, HelpMessage = "Resource group containing the SQL server")]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true, HelpMessage = "SQL server name")]
    [string]$ServerName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Database name to export")]
    [string]$DatabaseName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Storage account name for BACPAC storage")]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Storage container name")]
    [string]$ContainerName,
    
    [Parameter(Mandatory = $true, HelpMessage = "BACPAC file name")]
    [string]$BacpacFileName,
    
    [Parameter(Mandatory = $false, HelpMessage = "SQL server admin username (optional, uses Azure AD if not provided)")]
    [string]$AdminUser,
    
    [Parameter(Mandatory = $false, HelpMessage = "SQL server admin password (optional, uses Azure AD if not provided)")]
    [string]$AdminPassword,
    
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
            ResourceGroup = $ResourceGroupName
            Server = $ServerName
            Database = $DatabaseName
            StorageAccount = $StorageAccountName
            Container = $ContainerName
            BacpacFile = $BacpacFileName
            AuthMethod = if ($AdminUser) { "SQL" } else { "Azure AD" }
        }
        
        # Validate prerequisites
        Write-InfoLog "Validating prerequisites..."
        
        if (-not (Test-AzureConnection)) {
            Write-CriticalLog "Azure connection validation failed"
        }
        
        # Set subscription
        Set-AzureSubscription -SubscriptionId $SubscriptionId
        
        # Validate parameters
        if (-not $BacpacFileName.EndsWith(".bacpac")) {
            $BacpacFileName += ".bacpac"
            Write-InfoLog "Added .bacpac extension to filename: $BacpacFileName"
        }
        
        if ($AdminUser -and -not $AdminPassword) {
            Write-CriticalLog "AdminPassword is required when AdminUser is provided"
        }
        
        # Check if storage container exists, create if needed
        Write-InfoLog "Checking storage container existence..."
        $containerExists = az storage container exists --account-name $StorageAccountName --name $ContainerName --query "exists" -o tsv 2>$null
        
        if ($containerExists -ne "true") {
            Write-InfoLog "Creating storage container: $ContainerName"
            $createResult = az storage container create --account-name $StorageAccountName --name $ContainerName 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-CriticalLog "Failed to create storage container: $createResult"
            }
        }
        
        # Check if BACPAC file already exists
        if (Test-BlobExists -StorageAccountName $StorageAccountName -ContainerName $ContainerName -BlobName $BacpacFileName) {
            Write-WarningLog "BACPAC file already exists and will be overwritten: $BacpacFileName"
        }
        
        # Export database
        $exportSuccess = Export-SqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $ServerName -DatabaseName $DatabaseName -StorageAccountName $StorageAccountName -ContainerName $ContainerName -BacpacFileName $BacpacFileName -AdminUser $AdminUser -AdminPassword $AdminPassword
        
        if (-not $exportSuccess) {
            Write-CriticalLog "Database export failed"
        }
        
        # Verify BACPAC file was created
        Write-InfoLog "Verifying BACPAC file creation..."
        if (-not (Test-BlobExists -StorageAccountName $StorageAccountName -ContainerName $ContainerName -BlobName $BacpacFileName)) {
            Write-CriticalLog "BACPAC file was not found after export completion"
        }
        
        # Get file size for validation
        $blobInfo = az storage blob show --account-name $StorageAccountName --container-name $ContainerName --name $BacpacFileName --query "properties.contentLength" -o tsv 2>$null
        if ($blobInfo) {
            $fileSizeMB = [math]::Round([int]$blobInfo / 1MB, 2)
            Write-InfoLog "BACPAC file size: $fileSizeMB MB"
        }
        
        # Generate download URL for next steps
        $downloadUrl = Get-BlobDownloadUrl -StorageAccountName $StorageAccountName -ContainerName $ContainerName -BlobName $BacpacFileName -ExpiryHours 24
        
        Write-InfoLog "=== Azure SQL Database Export Completed Successfully ===" @{
            BacpacLocation = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BacpacFileName"
            DownloadUrl = $downloadUrl
            FileSizeMB = if ($blobInfo) { $fileSizeMB } else { "Unknown" }
        }
        
        # Output key information for CI/CD systems
        Write-Host "##[section]Export Results"
        Write-Host "BACPAC_URL=https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BacpacFileName"
        Write-Host "BACPAC_DOWNLOAD_URL=$downloadUrl"
        Write-Host "BACPAC_FILENAME=$BacpacFileName"
        if ($blobInfo) {
            Write-Host "BACPAC_SIZE_MB=$fileSizeMB"
        }
        
        exit 0
    }
    catch {
        Write-CriticalLog "Unhandled error in database export: $($_.Exception.Message)"
        exit 1
    }
}

# Execute main function
main
