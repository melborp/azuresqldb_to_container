# Push-ContainerImage.ps1
# Pushes a built container image to Azure Container Registry

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure Container Registry name")]
    [string]$RegistryName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Local image name")]
    [string]$ImageName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Image tag")]
    [string]$ImageTag,
    
    [Parameter(Mandatory = $false, HelpMessage = "Azure subscription ID")]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false, HelpMessage = "Use existing Docker login (skip Azure login)")]
    [switch]$UseExistingLogin,
    
    [Parameter(Mandatory = $false, HelpMessage = "Additional tags to apply")]
    [string[]]$AdditionalTags = @(),
    
    [Parameter(Mandatory = $false, HelpMessage = "Log level (Debug, Info, Warning, Error, Critical)")]
    [ValidateSet("Debug", "Info", "Warning", "Error", "Critical")]
    [string]$LogLevel = "Info"
)

# Import helper modules
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptDir\common\Logging-Helpers.ps1"
. "$scriptDir\common\Azure-Helpers.ps1"
. "$scriptDir\common\Docker-Helpers.ps1"

# Configure logging
Set-LogLevel $LogLevel
Set-LogPrefix "PUSH-CONTAINER"

function Connect-ToAzureContainerRegistry {
    param([string]$RegistryName, [string]$SubscriptionId)
    
    try {
        Write-InfoLog "Connecting to Azure Container Registry: $RegistryName"
        
        # Set subscription if provided
        if ($SubscriptionId) {
            Set-AzureSubscription -SubscriptionId $SubscriptionId
        }
        
        # Login to ACR
        Write-InfoLog "Authenticating with Azure Container Registry..."
        $loginResult = az acr login --name $RegistryName 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-CriticalLog "Failed to login to Azure Container Registry: $loginResult"
        }
        
        Write-InfoLog "Successfully authenticated with Azure Container Registry"
        return $true
    }
    catch {
        Write-CriticalLog "Error connecting to Azure Container Registry: $($_.Exception.Message)"
    }
}

function Get-RegistryImageName {
    param([string]$RegistryName, [string]$ImageName, [string]$Tag)
    
    # Remove any existing registry prefix from image name
    $cleanImageName = $ImageName -replace "^[^/]+\.azurecr\.io/", ""
    
    # Construct full registry image name
    $registryImageName = "$RegistryName.azurecr.io/$cleanImageName:$Tag"
    return $registryImageName
}

function Test-ImageExists {
    param([string]$ImageName)
    
    try {
        $result = docker images --format "{{.Repository}}:{{.Tag}}" $ImageName 2>$null
        return $result -eq $ImageName
    }
    catch {
        return $false
    }
}

function Push-ImageWithRetry {
    param([string]$ImageName, [int]$MaxRetries = 3)
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Write-InfoLog "Push attempt $attempt of $MaxRetries for: $ImageName"
            
            $pushResult = Push-DockerImageToRegistry -SourceImageName $ImageName -TargetImageName $ImageName
            
            if ($pushResult) {
                Write-InfoLog "Successfully pushed image: $ImageName"
                return $true
            }
        }
        catch {
            Write-WarningLog "Push attempt $attempt failed: $($_.Exception.Message)"
        }
        
        if ($attempt -lt $MaxRetries) {
            $waitTime = [math]::Pow(2, $attempt) * 5  # Exponential backoff
            Write-InfoLog "Waiting $waitTime seconds before retry..."
            Start-Sleep -Seconds $waitTime
        }
    }
    
    Write-CriticalLog "Failed to push image after $MaxRetries attempts"
}

function main {
    try {
        $localImageName = "${ImageName}:${ImageTag}"
        
        Write-InfoLog "=== Container Image Push Started ===" @{
            Registry = $RegistryName
            LocalImage = $localImageName
            SubscriptionId = $SubscriptionId
            UseExistingLogin = $UseExistingLogin.IsPresent
            AdditionalTags = ($AdditionalTags -join ", ")
        }
        
        # Validate prerequisites
        Write-InfoLog "Validating prerequisites..."
        
        if (-not (Test-DockerInstallation)) {
            Write-CriticalLog "Docker installation validation failed"
        }
        
        # Check if local image exists
        if (-not (Test-ImageExists -ImageName $localImageName)) {
            Write-CriticalLog "Local image not found: $localImageName"
        }
        
        # Validate registry name format
        if ($RegistryName -notmatch "^[a-zA-Z0-9]+$") {
            Write-CriticalLog "Invalid registry name format. Registry name should contain only alphanumeric characters."
        }
        
        # Connect to Azure and ACR if needed
        if (-not $UseExistingLogin) {
            if (-not (Test-AzureConnection)) {
                Write-CriticalLog "Azure connection validation failed"
            }
            
            Connect-ToAzureContainerRegistry -RegistryName $RegistryName -SubscriptionId $SubscriptionId
        } else {
            Write-InfoLog "Using existing Docker login as requested"
        }
        
        # Get registry image names
        $primaryRegistryImage = Get-RegistryImageName -RegistryName $RegistryName -ImageName $ImageName -Tag $ImageTag
        
        # Collect all images to push (primary + additional tags)
        $imagesToPush = @($primaryRegistryImage)
        
        foreach ($additionalTag in $AdditionalTags) {
            $additionalRegistryImage = Get-RegistryImageName -RegistryName $RegistryName -ImageName $ImageName -Tag $additionalTag
            $imagesToPush += $additionalRegistryImage
        }
        
        Write-InfoLog "Images to push: $($imagesToPush -join ', ')"
        
        # Tag and push each image
        foreach ($registryImage in $imagesToPush) {
            Write-InfoLog "Processing image: $registryImage"
            
            # Tag local image for registry
            if ($localImageName -ne $registryImage) {
                Write-InfoLog "Tagging image: $localImageName -> $registryImage"
                $tagResult = docker tag $localImageName $registryImage 2>&1
                
                if ($LASTEXITCODE -ne 0) {
                    Write-CriticalLog "Failed to tag image: $tagResult"
                }
            }
            
            # Push image with retry logic
            Push-ImageWithRetry -ImageName $registryImage
        }
        
        # Verify pushed images (optional verification)
        Write-InfoLog "Verifying pushed images..."
        foreach ($registryImage in $imagesToPush) {
            $repoAndTag = $registryImage.Split(':')
            $repo = $repoAndTag[0] -replace "^$RegistryName\.azurecr\.io/", ""
            $tag = $repoAndTag[1]
            
            Write-InfoLog "Checking repository: $repo, tag: $tag"
            $manifestResult = az acr repository show --name $RegistryName --repository $repo --query "name" -o tsv 2>$null
            
            if ($manifestResult -eq $repo) {
                Write-InfoLog "Verified image in registry: $registryImage"
            } else {
                Write-WarningLog "Could not verify image in registry: $registryImage"
            }
        }
        
        Write-InfoLog "=== Container Image Push Completed Successfully ===" @{
            Registry = "$RegistryName.azurecr.io"
            PushedImages = ($imagesToPush -join ", ")
            TotalImages = $imagesToPush.Count
        }
        
        # Output key information for CI/CD systems
        Write-Host "##[section]Push Results"
        Write-Host "REGISTRY_NAME=$RegistryName"
        Write-Host "REGISTRY_URL=$RegistryName.azurecr.io"
        Write-Host "PRIMARY_IMAGE=$primaryRegistryImage"
        Write-Host "PUSHED_IMAGES_COUNT=$($imagesToPush.Count)"
        
        for ($i = 0; $i -lt $imagesToPush.Count; $i++) {
            Write-Host "PUSHED_IMAGE_$i=$($imagesToPush[$i])"
        }
        
        exit 0
    }
    catch {
        Write-CriticalLog "Unhandled error in container push: $($_.Exception.Message)"
        exit 1
    }
}

# Execute main function
main
