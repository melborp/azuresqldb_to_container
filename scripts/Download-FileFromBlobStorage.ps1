# Download-FileFromBlobStorage.ps1
# Downloads files from Azure Blob Storage using Azure CLI authentication

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure Blob Storage URL (https://{account}.blob.core.windows.net/{container}/{blob})")]
    [string]$BlobUrl,
    
    [Parameter(Mandatory = $true, HelpMessage = "Local path where the file will be saved")]
    [string]$LocalPath,
    
    [Parameter(Mandatory = $false, HelpMessage = "Log level (Debug, Info, Warning, Error, Critical)")]
    [ValidateSet("Debug", "Info", "Warning", "Error", "Critical")]
    [string]$LogLevel = "Info",
    
    [Parameter(Mandatory = $false, HelpMessage = "Overwrite existing file if it exists")]
    [switch]$Force,
    
    [Parameter(Mandatory = $false, HelpMessage = "Verify file integrity after download")]
    [switch]$VerifyIntegrity
)

# Import helper modules
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptDir\common\Logging-Helpers.ps1"
. "$scriptDir\common\Azure-Helpers.ps1"

# Configure logging
Set-LogLevel $LogLevel
Set-LogPrefix "DOWNLOAD-BLOB"

function Test-BlobUrl {
    <#
    .SYNOPSIS
    Validates that the provided URL is a valid Azure Blob Storage URL
    #>
    param([string]$Url)
    
    if ($Url -notmatch "https://([^.]+)\.blob\.core\.windows\.net/([^/]+)/(.+)") {
        Write-CriticalLog "Invalid Azure Blob Storage URL format. Expected: https://{account}.blob.core.windows.net/{container}/{blob}"
    }
    
    return $true
}

function Get-BlobDetails {
    <#
    .SYNOPSIS
    Extracts storage account, container, and blob name from URL
    #>
    param([string]$BlobUrl)
    
    if ($BlobUrl -match "https://([^.]+)\.blob\.core\.windows\.net/([^/]+)/(.+)") {
        return @{
            StorageAccount = $matches[1]
            Container = $matches[2]
            BlobName = $matches[3]
        }
    }
    else {
        Write-CriticalLog "Failed to parse blob URL: $BlobUrl"
    }
}

function Test-LocalPathValid {
    <#
    .SYNOPSIS
    Validates the local path and creates directory if needed
    #>
    param([string]$Path, [bool]$Force)
    
    $directory = Split-Path $Path -Parent
    
    # Create directory if it doesn't exist
    if ($directory -and -not (Test-Path $directory)) {
        Write-InfoLog "Creating directory: $directory"
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    
    # Check if file exists
    if (Test-Path $Path) {
        if ($Force) {
            Write-InfoLog "File exists, will overwrite: $Path"
        }
        else {
            Write-CriticalLog "File already exists (use -Force to overwrite): $Path"
        }
    }
    
    return $true
}

function Invoke-BlobDownload {
    <#
    .SYNOPSIS
    Downloads the blob using Azure CLI or direct HTTP
    #>
    param([hashtable]$BlobDetails, [string]$LocalPath)
    
    $storageAccount = $BlobDetails.StorageAccount
    $container = $BlobDetails.Container
    $blobName = $BlobDetails.BlobName
    
    Write-InfoLog "Downloading blob..." @{
        StorageAccount = $storageAccount
        Container = $container
        BlobName = $blobName
        LocalPath = $LocalPath
    }
    
    # Try Azure CLI download first (uses current authentication)
    try {
        Write-InfoLog "Attempting download using Azure CLI authentication..."
        
        $downloadResult = az storage blob download `
            --account-name $storageAccount `
            --container-name $container `
            --name $blobName `
            --file $LocalPath `
            --auth-mode login `
            --overwrite 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-InfoLog "Successfully downloaded using Azure CLI authentication"
            return $true
        }
        else {
            Write-WarningLog "Azure CLI download failed: $downloadResult"
        }
    }
    catch {
        Write-WarningLog "Azure CLI download error: $($_.Exception.Message)"
    }
    
    # Fallback to storage account key if available
    try {
        Write-InfoLog "Attempting download using storage account key..."
        
        $storageKey = az storage account keys list --account-name $storageAccount --query "[0].value" --output tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $storageKey) {
            $downloadResult = az storage blob download `
                --account-name $storageAccount `
                --account-key $storageKey `
                --container-name $container `
                --name $blobName `
                --file $LocalPath `
                --overwrite 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-InfoLog "Successfully downloaded using storage account key"
                return $true
            }
            else {
                Write-WarningLog "Storage key download failed: $downloadResult"
            }
        }
    }
    catch {
        Write-WarningLog "Storage key download error: $($_.Exception.Message)"
    }
    
    # Final fallback to SAS token generation
    try {
        Write-InfoLog "Attempting download using generated SAS token..."
        
        $sasUrl = Get-BlobDownloadUrl -StorageAccountName $storageAccount -ContainerName $container -BlobName $blobName -ExpiryHours 1
        if ($sasUrl) {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($sasUrl, $LocalPath)
            $webClient.Dispose()
            
            Write-InfoLog "Successfully downloaded using SAS token"
            return $true
        }
    }
    catch {
        Write-WarningLog "SAS token download error: $($_.Exception.Message)"
    }
    
    Write-CriticalLog "All download methods failed for blob: $blobName"
    return $false
}

function Test-DownloadedFile {
    <#
    .SYNOPSIS
    Verifies the downloaded file integrity and provides information
    #>
    param([string]$FilePath, [bool]$VerifyIntegrity)
    
    if (-not (Test-Path $FilePath)) {
        Write-CriticalLog "Downloaded file not found: $FilePath"
    }
    
    $fileInfo = Get-Item $FilePath
    $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
    
    Write-InfoLog "Download completed successfully" @{
        FilePath = $FilePath
        SizeMB = $fileSizeMB
        LastModified = $fileInfo.LastWriteTime
    }
    
    if ($VerifyIntegrity) {
        Write-InfoLog "Verifying file integrity..."
        
        # Basic file validation
        try {
            $hash = Get-FileHash $FilePath -Algorithm SHA256
            Write-InfoLog "File SHA256 hash: $($hash.Hash)"
            
            # Additional validation for common file types
            $extension = $fileInfo.Extension.ToLower()
            switch ($extension) {
                ".bacpac" {
                    # BACPAC files are ZIP archives
                    try {
                        Add-Type -AssemblyName System.IO.Compression.FileSystem
                        $archive = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
                        $entryCount = $archive.Entries.Count
                        $archive.Dispose()
                        Write-InfoLog "BACPAC file validation: $entryCount entries found"
                    }
                    catch {
                        Write-WarningLog "BACPAC file validation failed: $($_.Exception.Message)"
                    }
                }
                ".sql" {
                    # SQL files should be readable text
                    try {
                        $content = Get-Content $FilePath -TotalCount 10
                        if ($content) {
                            Write-InfoLog "SQL file validation: Content readable"
                        }
                        else {
                            Write-WarningLog "SQL file appears to be empty"
                        }
                    }
                    catch {
                        Write-WarningLog "SQL file validation failed: $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            Write-WarningLog "File integrity verification failed: $($_.Exception.Message)"
        }
    }
    
    return $true
}

function main {
    try {
        Write-InfoLog "=== Blob Storage Download Started ===" @{
            BlobUrl = $BlobUrl
            LocalPath = $LocalPath
            Force = $Force.IsPresent
            VerifyIntegrity = $VerifyIntegrity.IsPresent
            LogLevel = $LogLevel
        }
        
        # Validate input parameters
        Test-BlobUrl -Url $BlobUrl
        Test-LocalPathValid -Path $LocalPath -Force $Force.IsPresent
        
        # Parse blob URL
        $blobDetails = Get-BlobDetails -BlobUrl $BlobUrl
        
        # Download the blob
        $downloadSuccess = Invoke-BlobDownload -BlobDetails $blobDetails -LocalPath $LocalPath
        
        if (-not $downloadSuccess) {
            Write-CriticalLog "Failed to download blob from storage"
        }
        
        # Verify downloaded file
        Test-DownloadedFile -FilePath $LocalPath -VerifyIntegrity $VerifyIntegrity.IsPresent
        
        Write-InfoLog "=== Blob Storage Download Completed Successfully ===" @{
            LocalPath = $LocalPath
            FileSize = "$([math]::Round((Get-Item $LocalPath).Length / 1MB, 2)) MB"
            StorageAccount = $blobDetails.StorageAccount
            Container = $blobDetails.Container
            BlobName = $blobDetails.BlobName
        }
        
        # Output key information for CI/CD systems
        Write-Host "##[section]Download Results"
        Write-Host "DOWNLOADED_FILE=$LocalPath"
        Write-Host "FILE_SIZE_MB=$([math]::Round((Get-Item $LocalPath).Length / 1MB, 2))"
        Write-Host "STORAGE_ACCOUNT=$($blobDetails.StorageAccount)"
        Write-Host "CONTAINER_NAME=$($blobDetails.Container)"
        Write-Host "BLOB_NAME=$($blobDetails.BlobName)"
        
        exit 0
    }
    catch {
        Write-CriticalLog "Unhandled error in blob download: $($_.Exception.Message)"
        exit 1
    }
}

# Execute main function
main
