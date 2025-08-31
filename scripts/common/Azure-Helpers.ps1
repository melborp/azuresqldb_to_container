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
    Exports an Azure SQL Database to BACPAC format
    
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
        [string]$AdminPassword
    )
    
    try {
        Write-InfoLog "Starting database export..." @{
            ResourceGroup = $ResourceGroupName
            Server = $ServerName
            Database = $DatabaseName
            StorageAccount = $StorageAccountName
            Container = $ContainerName
            BacpacFile = $BacpacFileName
        }
        
        # Get storage account key
        Write-InfoLog "Retrieving storage account key..."
        $storageKey = az storage account keys list --resource-group $ResourceGroupName --account-name $StorageAccountName --query "[0].value" -o tsv
        if ($LASTEXITCODE -ne 0 -or -not $storageKey) {
            Write-CriticalLog "Failed to retrieve storage account key"
        }
        
        # Build export command
        $exportArgs = @(
            "sql", "db", "export"
            "--resource-group", $ResourceGroupName
            "--server", $ServerName
            "--name", $DatabaseName
            "--storage-key-type", "StorageAccessKey"
            "--storage-key", $storageKey
            "--storage-uri", "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BacpacFileName"
        )
        
        # Add authentication - SQL credentials are required for az sql db export
        if ($AdminUser -and $AdminPassword) {
            $exportArgs += @("--admin-user", $AdminUser, "--admin-password", $AdminPassword)
            Write-InfoLog "Using SQL authentication for export"
        } else {
            Write-CriticalLog "SQL admin credentials are required for database export. Azure CLI 'az sql db export' does not support Azure AD authentication. Please provide -AdminUser and -AdminPassword parameters with SQL Server admin credentials."
        }
        
        # Start export
        Write-InfoLog "Initiating database export operation..."
        Write-InfoLog "Running command: az $($exportArgs -join ' ')"
        $exportOutput = & az @exportArgs 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-CriticalLog "Database export initiation failed: $exportOutput"
        }
        
        # Try to parse as JSON, handle errors gracefully
        try {
            $exportResult = $exportOutput | ConvertFrom-Json
        }
        catch {
            Write-CriticalLog "Failed to parse export command output as JSON. Raw output: $exportOutput"
        }
        
        $operationId = $exportResult.name
        Write-InfoLog "Export operation started with ID: $operationId"
        
        # Monitor export progress
        Write-InfoLog "Monitoring export progress..."
        do {
            Start-Sleep -Seconds 30
            $status = az sql db export show --resource-group $ResourceGroupName --server $ServerName --name $operationId --query "status" -o tsv
            Write-InfoLog "Export status: $status"
        } while ($status -eq "InProgress")
        
        if ($status -eq "Succeeded") {
            Write-InfoLog "Database export completed successfully" @{
                OperationId = $operationId
                BacpacLocation = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BacpacFileName"
            }
            return $true
        } else {
            Write-CriticalLog "Database export failed with status: $status"
        }
    }
    catch {
        Write-CriticalLog "Error during database export: $($_.Exception.Message)"
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
