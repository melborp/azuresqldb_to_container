# Azure-Helpers.ps1
# Azure-specific helper functions for authentication and resource management

. "$PSScriptRoot\Logging-Helpers.ps1"

function Test-AzureConnection {
    <#
    .SYNOPSIS
    Tests if Azure CLI is installed and user is authenticated
    
    .DESCRIPTION
    Validates Azure CLI installation and authentication status
    
    .OUTPUTS
    Boolean indicating if Azure connection is ready
    #>
    
    try {
        Write-InfoLog "Testing Azure CLI connection..."
        
        # Check if Azure CLI is installed
        $azVersion = az version 2>$null | ConvertFrom-Json
        if (-not $azVersion) {
            Write-ErrorLog "Azure CLI is not installed or not in PATH"
            return $false
        }
        
        Write-InfoLog "Azure CLI version: $($azVersion.'azure-cli')"
        
        # Check if user is logged in
        $account = az account show 2>$null | ConvertFrom-Json
        if (-not $account) {
            Write-ErrorLog "Not logged in to Azure. Please run 'az login'"
            return $false
        }
        
        Write-InfoLog "Connected to Azure subscription: $($account.name) ($($account.id))"
        return $true
    }
    catch {
        Write-ErrorLog "Failed to test Azure connection: $($_.Exception.Message)"
        return $false
    }
}

function Set-AzureSubscription {
    <#
    .SYNOPSIS
    Sets the active Azure subscription
    
    .PARAMETER SubscriptionId
    The Azure subscription ID to set as active
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )
    
    try {
        Write-InfoLog "Setting Azure subscription to: $SubscriptionId"
        
        $result = az account set --subscription $SubscriptionId 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-CriticalLog "Failed to set Azure subscription: $result"
        }
        
        # Verify the subscription was set
        $currentSub = az account show --query "id" -o tsv
        if ($currentSub -ne $SubscriptionId) {
            Write-CriticalLog "Subscription verification failed. Expected: $SubscriptionId, Got: $currentSub"
        }
        
        Write-InfoLog "Successfully set Azure subscription"
    }
    catch {
        Write-CriticalLog "Error setting Azure subscription: $($_.Exception.Message)"
    }
}

function Export-SqlDatabase {
    <#
    .SYNOPSIS
    Exports an Azure SQL Database to BACPAC format using SqlPackage utility
    
    .PARAMETER ResourceGroupName
    The resource group containing the SQL server
    
    .PARAMETER ServerName
    The SQL server name
    
    .PARAMETER DatabaseName
    The database to export
    
    .PARAMETER StorageAccountName
    The storage account for BACPAC storage
    
    .PARAMETER ContainerName
    The storage container name
    
    .PARAMETER BacpacFileName
    The BACPAC file name
    
    .PARAMETER AdminUser
    SQL server admin username (optional, uses Azure AD if not provided)
    
    .PARAMETER AdminPassword
    SQL server admin password (optional, uses Azure AD if not provided)
    
    .PARAMETER TenantId
    Azure AD tenant ID (optional, will attempt to detect automatically)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory = $true)]
        [string]$BacpacFileName,
        
        [Parameter(Mandatory = $false)]
        [string]$AdminUser,
        
        [Parameter(Mandatory = $false)]
        [string]$AdminPassword,
        
        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )
    
    try {
        Write-InfoLog "Starting database export using SqlPackage..." @{
            ResourceGroup = $ResourceGroupName
            Server = $ServerName
            Database = $DatabaseName
            StorageAccount = $StorageAccountName
            Container = $ContainerName
            BacpacFile = $BacpacFileName
        }
        
        # Check if SqlPackage is available
        Write-InfoLog "Checking SqlPackage availability..."
        try {
            $sqlPackageVersion = & sqlpackage /version 2>$null
            Write-InfoLog "SqlPackage found: $sqlPackageVersion"
        }
        catch {
            Write-CriticalLog "SqlPackage utility not found. Please install SqlPackage from https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download"
        }
        
        # Create local export path
        $tempDir = [System.IO.Path]::GetTempPath()
        $localBacpacPath = Join-Path $tempDir $BacpacFileName
        Write-InfoLog "Local BACPAC path: $localBacpacPath"
        
        # Build connection string
        $serverFqdn = if ($ServerName.Contains('.')) { $ServerName } else { "$ServerName.database.windows.net" }
        $connectionString = "Data Source=$serverFqdn;Initial Catalog=$DatabaseName;"
        
        # Build SqlPackage arguments
        $sqlPackageArgs = @(
            "/Action:Export"
            "/TargetFile:$localBacpacPath"
            "/SourceConnectionString:$connectionString"
        )
        
        # Add authentication
        if ($AdminUser -and $AdminPassword) {
            # SQL Authentication
            $sqlPackageArgs += "/SourceUser:$AdminUser"
            $sqlPackageArgs += "/SourcePassword:$AdminPassword"
            Write-InfoLog "Using SQL authentication for export"
        } else {
            # Azure AD Authentication
            $sqlPackageArgs += "/UniversalAuthentication:True"
            
            # Get tenant ID if not provided
            if (-not $TenantId) {
                Write-InfoLog "Detecting Azure AD tenant ID..."
                $tenantInfo = az account show --query "tenantId" -o tsv 2>$null
                if ($LASTEXITCODE -eq 0 -and $tenantInfo) {
                    $TenantId = $tenantInfo.Trim()
                    Write-InfoLog "Detected tenant ID: $TenantId"
                } else {
                    Write-WarningLog "Could not detect tenant ID automatically. Proceeding without explicit tenant ID."
                }
            }
            
            if ($TenantId) {
                $sqlPackageArgs += "/TenantId:$TenantId"
            }
            
            Write-InfoLog "Using Azure AD authentication for export"
        }
        
        # Execute SqlPackage export
        Write-InfoLog "Executing SqlPackage export..." @{
            Command = "sqlpackage $($sqlPackageArgs -join ' ')"
        }
        
        $exportResult = & sqlpackage @sqlPackageArgs 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-CriticalLog "SqlPackage export failed: $exportResult"
        }
        
        # Verify local BACPAC file was created
        if (-not (Test-Path $localBacpacPath)) {
            Write-CriticalLog "BACPAC file was not created at expected location: $localBacpacPath"
        }
        
        $fileSize = (Get-Item $localBacpacPath).Length
        Write-InfoLog "BACPAC export completed successfully" @{
            LocalPath = $localBacpacPath
            FileSizeBytes = $fileSize
            FileSizeMB = [math]::Round($fileSize / 1MB, 2)
        }
        
        # Upload to Azure Blob Storage
        Write-InfoLog "Uploading BACPAC to Azure Blob Storage..."
        $uploadSuccess = Export-BacpacToStorage -LocalBacpacPath $localBacpacPath -StorageAccountName $StorageAccountName -ContainerName $ContainerName -BlobName $BacpacFileName -ResourceGroupName $ResourceGroupName
        
        if (-not $uploadSuccess) {
            Write-CriticalLog "Failed to upload BACPAC to Azure Blob Storage"
        }
        
        # Cleanup local file
        Write-InfoLog "Cleaning up local BACPAC file..."
        Remove-Item $localBacpacPath -Force -ErrorAction SilentlyContinue
        
        Write-InfoLog "Database export completed successfully" @{
            BacpacLocation = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BacpacFileName"
        }
        
        return $true
    }
    catch {
        Write-CriticalLog "Error during database export: $($_.Exception.Message)"
        
        # Cleanup on error
        if ($localBacpacPath -and (Test-Path $localBacpacPath)) {
            Remove-Item $localBacpacPath -Force -ErrorAction SilentlyContinue
        }
        
        return $false
    }
}

function Export-BacpacToStorage {
    <#
    .SYNOPSIS
    Uploads a local BACPAC file to Azure Blob Storage
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LocalBacpacPath,
        
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory = $true)]
        [string]$BlobName,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )
    
    try {
        # Get storage account key
        Write-InfoLog "Retrieving storage account key..."
        $storageKey = az storage account keys list --resource-group $ResourceGroupName --account-name $StorageAccountName --query "[0].value" -o tsv
        if ($LASTEXITCODE -ne 0 -or -not $storageKey) {
            Write-CriticalLog "Failed to retrieve storage account key"
        }
        
        # Upload file
        Write-InfoLog "Uploading BACPAC file to blob storage..."
        $uploadResult = az storage blob upload --account-name $StorageAccountName --account-key $storageKey --container-name $ContainerName --name $BlobName --file $LocalBacpacPath --auth-mode key 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-CriticalLog "Failed to upload BACPAC to blob storage: $uploadResult"
        }
        
        Write-InfoLog "BACPAC uploaded successfully to blob storage"
        return $true
    }
    catch {
        Write-CriticalLog "Error uploading BACPAC to storage: $($_.Exception.Message)"
        return $false
    }
}

function Test-BlobExists {
    <#
    .SYNOPSIS
    Tests if a blob exists in Azure Storage
    
    .PARAMETER StorageAccountName
    The storage account name
    
    .PARAMETER ContainerName
    The container name
    
    .PARAMETER BlobName
    The blob name to check
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory = $true)]
        [string]$BlobName
    )
    
    try {
        $result = az storage blob exists --account-name $StorageAccountName --container-name $ContainerName --name $BlobName --query "exists" -o tsv
        return $result -eq "true"
    }
    catch {
        Write-ErrorLog "Error checking blob existence: $($_.Exception.Message)"
        return $false
    }
}

function Get-BlobDownloadUrl {
    <#
    .SYNOPSIS
    Generates a download URL for a blob
    
    .PARAMETER StorageAccountName
    The storage account name
    
    .PARAMETER ContainerName
    The container name
    
    .PARAMETER BlobName
    The blob name
    
    .PARAMETER ExpiryHours
    Hours until the SAS token expires (default: 24)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory = $true)]
        [string]$BlobName,
        
        [Parameter(Mandatory = $false)]
        [int]$ExpiryHours = 24
    )
    
    try {
        $expiryDate = (Get-Date).AddHours($ExpiryHours).ToString("yyyy-MM-ddTHH:mm:ssZ")
        
        $sasToken = az storage blob generate-sas --account-name $StorageAccountName --container-name $ContainerName --name $BlobName --permissions r --expiry $expiryDate -o tsv
        
        if ($LASTEXITCODE -ne 0 -or -not $sasToken) {
            Write-CriticalLog "Failed to generate SAS token for blob"
        }
        
        $downloadUrl = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BlobName?$sasToken"
        return $downloadUrl
    }
    catch {
        Write-CriticalLog "Error generating blob download URL: $($_.Exception.Message)"
    }
}
