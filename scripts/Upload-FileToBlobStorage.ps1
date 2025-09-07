# Upload-FileToBlobStorage.ps1
# Uploads any file to Azure Blob Storage using Azure CLI
#
# This script provides a generic file upload capability to Azure Blob Storage.
# It can be used for BACPAC files, logs, backups, or any other files.
#
# Prerequisites:
# - Azure CLI must be installed and authenticated (az login)
# - Appropriate permissions for the storage account

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure subscription ID")]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true, HelpMessage = "Local file path to upload")]
    [string]$FilePath,
    
    [Parameter(Mandatory = $true, HelpMessage = "Storage account name")]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Storage container name")]
    [string]$ContainerName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Blob name (defaults to filename if not provided)")]
    [string]$BlobName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Overwrite existing blob")]
    [switch]$Overwrite,
    
    [Parameter(Mandatory = $false, HelpMessage = "Generate SAS URL for download (hours, default: 24)")]
    [int]$GenerateSasUrlHours = 0,
    
    [Parameter(Mandatory = $false, HelpMessage = "Content type for the blob (auto-detected if not provided)")]
    [string]$ContentType,
    
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
Set-LogPrefix "UPLOAD-BLOB"

function main {
    try {
        Write-InfoLog "=== File Upload to Blob Storage Started ===" @{
            SubscriptionId = $SubscriptionId
            FilePath = $FilePath
            StorageAccount = $StorageAccountName
            Container = $ContainerName
            BlobName = $BlobName
            Overwrite = $Overwrite.IsPresent
        }
        
        # Validate prerequisites
        Write-InfoLog "Validating prerequisites..."
        
        if (-not (Test-AzureConnection)) {
            Write-CriticalLog "Azure connection validation failed"
        }
        
        # Set subscription
        Set-AzureSubscription -SubscriptionId $SubscriptionId
        
        # Validate file exists
        if (-not (Test-Path $FilePath)) {
            Write-CriticalLog "File not found: $FilePath"
        }
        
        $fileInfo = Get-Item $FilePath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        
        Write-InfoLog "File details:" @{
            FullPath = $fileInfo.FullName
            Name = $fileInfo.Name
            SizeMB = $fileSizeMB
            SizeBytes = $fileInfo.Length
            LastModified = $fileInfo.LastWriteTime
        }
        
        # Set blob name if not provided
        if (-not $BlobName) {
            $BlobName = $fileInfo.Name
            Write-InfoLog "Using filename as blob name: $BlobName"
        }
        
        # Auto-detect content type if not provided
        if (-not $ContentType) {
            $ContentType = switch ($fileInfo.Extension.ToLower()) {
                ".bacpac" { "application/octet-stream" }
                ".sql" { "text/plain" }
                ".json" { "application/json" }
                ".xml" { "application/xml" }
                ".txt" { "text/plain" }
                ".log" { "text/plain" }
                ".zip" { "application/zip" }
                ".tar" { "application/x-tar" }
                ".gz" { "application/gzip" }
                default { "application/octet-stream" }
            }
            Write-InfoLog "Auto-detected content type: $ContentType"
        }
        
        # Check if storage container exists, create if needed
        Write-InfoLog "Checking storage container existence..."
        $containerExists = az storage container exists --account-name $StorageAccountName --name $ContainerName --query "exists" -o tsv 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-CriticalLog "Failed to check container existence. Verify storage account name and permissions."
        }
        
        if ($containerExists -ne "true") {
            Write-InfoLog "Creating storage container: $ContainerName"
            $createResult = az storage container create --account-name $StorageAccountName --name $ContainerName 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-CriticalLog "Failed to create storage container: $createResult"
            }
            Write-InfoLog "Container created successfully"
        } else {
            Write-InfoLog "Container exists: $ContainerName"
        }
        
        # Check if blob already exists
        $blobExists = az storage blob exists --account-name $StorageAccountName --container-name $ContainerName --name $BlobName --query "exists" -o tsv 2>$null
        
        if ($blobExists -eq "true") {
            if ($Overwrite) {
                Write-WarningLog "Blob already exists and will be overwritten: $BlobName"
            } else {
                Write-CriticalLog "Blob already exists: $BlobName. Use -Overwrite to replace it."
            }
        }
        
        # Upload file to blob storage
        Write-InfoLog "Uploading file to blob storage..." @{
            SourceFile = $FilePath
            TargetBlob = $BlobName
            StorageAccount = $StorageAccountName
            Container = $ContainerName
            ContentType = $ContentType
        }
        
        $uploadArgs = @(
            "storage", "blob", "upload"
            "--account-name", $StorageAccountName
            "--container-name", $ContainerName
            "--name", $BlobName
            "--file", $FilePath
            "--content-type", $ContentType
        )
        
        if ($Overwrite) {
            $uploadArgs += "--overwrite"
        }
        
        $uploadStart = Get-Date
        $uploadResult = & az @uploadArgs 2>&1
        $uploadEnd = Get-Date
        $uploadDuration = ($uploadEnd - $uploadStart).TotalSeconds
        
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog "Upload output: $uploadResult"
            Write-CriticalLog "Failed to upload file to blob storage"
        }
        
        Write-InfoLog "File uploaded successfully" @{
            UploadDurationSeconds = [math]::Round($uploadDuration, 2)
            ThroughputMBps = if ($uploadDuration -gt 0) { [math]::Round($fileSizeMB / $uploadDuration, 2) } else { "N/A" }
        }
        
        # Verify upload
        Write-InfoLog "Verifying upload..."
        $blobInfo = az storage blob show --account-name $StorageAccountName --container-name $ContainerName --name $BlobName --query "{size:properties.contentLength, lastModified:properties.lastModified, contentType:properties.contentType}" -o json 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-WarningLog "Could not verify upload, but upload command succeeded"
        } else {
            $blobDetails = $blobInfo | ConvertFrom-Json
            $uploadedSizeMB = [math]::Round([int]$blobDetails.size / 1MB, 2)
            
            Write-InfoLog "Upload verified successfully" @{
                BlobSize = $blobDetails.size
                BlobSizeMB = $uploadedSizeMB
                LastModified = $blobDetails.lastModified
                ContentType = $blobDetails.contentType
            }
            
            # Verify file size matches
            if ([int]$blobDetails.size -ne $fileInfo.Length) {
                Write-WarningLog "File size mismatch! Local: $($fileInfo.Length) bytes, Blob: $($blobDetails.size) bytes"
            }
        }
        
        # Generate blob URL
        $blobUrl = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BlobName"
        
        # Generate SAS URL if requested
        $sasUrl = $null
        if ($GenerateSasUrlHours -gt 0) {
            Write-InfoLog "Generating SAS URL for $GenerateSasUrlHours hours..."
            $expiryTime = (Get-Date).AddHours($GenerateSasUrlHours).ToString("yyyy-MM-ddTHH:mm:ssZ")
            
            $sasToken = az storage blob generate-sas --account-name $StorageAccountName --container-name $ContainerName --name $BlobName --permissions r --expiry $expiryTime --https-only --output tsv 2>$null
            
            if ($LASTEXITCODE -eq 0 -and $sasToken) {
                $sasUrl = "$blobUrl?$sasToken"
                Write-InfoLog "SAS URL generated successfully (expires: $expiryTime)"
            } else {
                Write-WarningLog "Failed to generate SAS URL"
            }
        }
        
        Write-InfoLog "=== File Upload to Blob Storage Completed Successfully ===" @{
            BlobUrl = $blobUrl
            BlobName = $BlobName
            FileSizeMB = $fileSizeMB
            UploadDurationSeconds = [math]::Round($uploadDuration, 2)
        }
        
        # Output key information for automation
        Write-Host "##[section]Upload Results"
        Write-Host "BLOB_URL=$blobUrl"
        Write-Host "BLOB_NAME=$BlobName"
        Write-Host "BLOB_SIZE_MB=$fileSizeMB"
        Write-Host "BLOB_SIZE_BYTES=$($fileInfo.Length)"
        Write-Host "UPLOAD_DURATION_SECONDS=$([math]::Round($uploadDuration, 2))"
        if ($sasUrl) {
            Write-Host "BLOB_SAS_URL=$sasUrl"
            Write-Host "SAS_EXPIRY_HOURS=$GenerateSasUrlHours"
        }
        
        exit 0
    }
    catch {
        Write-CriticalLog "Unhandled error in file upload: $($_.Exception.Message)"
        exit 1
    }
}

# Execute main function
main
