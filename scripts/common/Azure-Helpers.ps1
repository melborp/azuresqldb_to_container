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
            Write-InfoLog "Using Azure AD authentication for export"
            
            # For CI/CD environments, use access token authentication
            if ($env:SYSTEM_TEAMPROJECTID -or $env:GITHUB_ACTIONS -or $env:CI -or $env:BUILD_BUILDID) {
                Write-InfoLog "CI/CD environment detected - using access token authentication"
                
                # Get SQL Database specific token (not Azure Management token)
                Write-InfoLog "Getting SQL Database access token..."
                $tokenCheck = az account get-access-token --resource "https://database.windows.net/" --query "accessToken" -o tsv 2>$null
                if ($LASTEXITCODE -ne 0 -or -not $tokenCheck) {
                    Write-CriticalLog "No valid Azure CLI authentication found. In CI/CD environments, ensure the Azure CLI task or azure/login action has been executed with appropriate service principal credentials."
                }
                
                # Use SQL Database token for SqlPackage authentication
                $sqlPackageArgs += "/AccessToken:$tokenCheck"
                
            } else {
                # Interactive environment - try Universal Authentication first
                Write-InfoLog "Interactive environment - using Universal Authentication"
                $sqlPackageArgs += "/UniversalAuthentication:True"
                
                # Get tenant ID if not provided (helps with authentication)
                if (-not $TenantId) {
                    Write-InfoLog "Detecting Azure AD tenant ID..."
                    $tenantInfo = az account show --query "tenantId" -o tsv 2>$null
                    if ($LASTEXITCODE -eq 0 -and $tenantInfo) {
                        $TenantId = $tenantInfo.Trim()
                        Write-InfoLog "Detected tenant ID: $TenantId"
                    }
                }
                
                # Add tenant ID if available (required for some environments)
                if ($TenantId) {
                    $sqlPackageArgs += "/TenantId:$TenantId"
                }
            }
        }
        
        # Execute SqlPackage export
        Write-InfoLog "Executing SqlPackage export..." @{
            Command = "sqlpackage $($sqlPackageArgs -join ' ')"
            ParameterCount = $sqlPackageArgs.Count
        }
        
        # Debug: Show actual parameters (excluding sensitive data)
        $debugArgs = $sqlPackageArgs | ForEach-Object { 
            if ($_ -like "/SourcePassword:*" -or $_ -like "/AccessToken:*") { 
                $_.Split(':')[0] + ":[REDACTED]" 
            } else { 
                $_ 
            } 
        }
        Write-InfoLog "SqlPackage parameters: $($debugArgs -join ' ')"
        
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
        $uploadResult = az storage blob upload --account-name $StorageAccountName --account-key $storageKey --container-name $ContainerName --name $BlobName --file $LocalBacpacPath --auth-mode key --overwrite 2>&1
        
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

function Download-BacpacFromStorage {
    <#
    .SYNOPSIS
    Downloads a BACPAC file from Azure Blob Storage using Azure CLI authentication or SAS token
    
    .PARAMETER BlobUrl
    The full blob URL (https://account.blob.core.windows.net/container/blob or with SAS token)
    
    .PARAMETER LocalPath
    The local path where the file should be downloaded
    
    .PARAMETER ResourceGroupName
    The resource group containing the storage account (optional for SAS token generation)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BlobUrl,
        
        [Parameter(Mandatory = $true)]
        [string]$LocalPath,
        
        [Parameter(Mandatory = $false)]
        [string]$ResourceGroupName = $null
    )
    
    try {
        # Check if URL already contains SAS token
        if ($BlobUrl -match '\?.*sv=') {
            Write-InfoLog "URL contains SAS token, using direct download..."
            
            # Use WebClient for SAS token URLs
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($BlobUrl, $LocalPath)
            $webClient.Dispose()
            
            # Verify the file was downloaded
            if (-not (Test-Path $LocalPath)) {
                Write-CriticalLog "BACPAC file was not downloaded successfully"
            }
            
            $fileSize = (Get-Item $LocalPath).Length
            Write-InfoLog "BACPAC downloaded successfully" @{
                LocalPath = $LocalPath
                SizeBytes = $fileSize
            }
            
            return $true
        }
        
        # Parse the blob URL to extract components
        $uri = [System.Uri]$BlobUrl
        $pathParts = $uri.AbsolutePath.TrimStart('/').Split('/', 2)
        
        if ($pathParts.Length -ne 2) {
            Write-CriticalLog "Invalid blob URL format. Expected: https://account.blob.core.windows.net/container/blob"
        }
        
        $storageAccountName = $uri.Host.Split('.')[0]
        $containerName = $pathParts[0]
        $blobName = $pathParts[1]
        
        Write-InfoLog "Downloading blob with Azure CLI authentication..." @{
            StorageAccount = $storageAccountName
            Container = $containerName
            Blob = $blobName
            LocalPath = $LocalPath
        }
        
        # Try to download using Azure CLI with current authentication
        $downloadResult = az storage blob download --account-name $storageAccountName --container-name $containerName --name $blobName --file $LocalPath --auth-mode login --overwrite 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog "Failed to download with login auth, trying with account key..."
            
            # If direct download fails and we have resource group, try with account key
            if ($ResourceGroupName) {
                $storageKey = az storage account keys list --resource-group $ResourceGroupName --account-name $storageAccountName --query "[0].value" -o tsv 2>$null
                
                if ($LASTEXITCODE -eq 0 -and $storageKey) {
                    $downloadResult = az storage blob download --account-name $storageAccountName --account-key $storageKey --container-name $containerName --name $blobName --file $LocalPath --overwrite 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        Write-CriticalLog "Failed to download BACPAC with account key: $downloadResult"
                    }
                } else {
                    Write-ErrorLog "Could not retrieve account key, trying to generate SAS token..."
                    
                    # Try to generate SAS token as fallback
                    try {
                        $sasUrl = Get-BlobDownloadUrl -StorageAccountName $storageAccountName -ContainerName $containerName -BlobName $blobName -ExpiryHours 1
                        if ($sasUrl) {
                            Write-InfoLog "Generated SAS token, downloading with WebClient..."
                            $webClient = New-Object System.Net.WebClient
                            $webClient.DownloadFile($sasUrl, $LocalPath)
                            $webClient.Dispose()
                        } else {
                            Write-CriticalLog "Failed to download BACPAC with all available methods: $downloadResult"
                        }
                    }
                    catch {
                        Write-CriticalLog "Failed to download BACPAC with login auth and could not generate SAS token: $downloadResult"
                    }
                }
            } else {
                Write-CriticalLog "Failed to download BACPAC with login auth: $downloadResult"
            }
        }
        
        # Verify the file was downloaded
        if (-not (Test-Path $LocalPath)) {
            Write-CriticalLog "BACPAC file was not downloaded successfully"
        }
        
        $fileSize = (Get-Item $LocalPath).Length
        Write-InfoLog "BACPAC downloaded successfully" @{
            LocalPath = $LocalPath
            SizeBytes = $fileSize
        }
        
        return $true
    }
    catch {
        Write-CriticalLog "Error downloading BACPAC from storage: $($_.Exception.Message)"
        return $false
    }
}
