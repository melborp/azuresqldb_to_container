# Docker-Helpers.ps1
# Docker-specific helper functions for container management

. "$PSScriptRoot\Logging-Helpers.ps1"

function Test-DockerInstallation {
    <#
    .SYNOPSIS
    Tests if Docker is installed and running
    
    .DESCRIPTION
    Validates Docker installation and daemon status
    
    .OUTPUTS
    Boolean indicating if Docker is ready
    #>
    
    try {
        Write-InfoLog "Testing Docker installation..."
        
        # Check if Docker is installed
        $dockerVersion = docker --version 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog "Docker is not installed or not in PATH"
            return $false
        }
        
        Write-InfoLog "Docker version: $dockerVersion"
        
        # Check if Docker daemon is running
        $dockerInfo = docker info 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog "Docker daemon is not running"
            return $false
        }
        
        Write-InfoLog "Docker daemon is running"
        return $true
    }
    catch {
        Write-ErrorLog "Failed to test Docker installation: $($_.Exception.Message)"
        return $false
    }
}

function Build-DockerImage {
    <#
    .SYNOPSIS
    Builds a Docker image with specified parameters
    
    .PARAMETER ImageName
    The name for the Docker image
    
    .PARAMETER ImageTag
    The tag for the Docker image
    
    .PARAMETER DockerfilePath
    Path to the Dockerfile
    
    .PARAMETER BuildContext
    Build context directory
    
    .PARAMETER BuildArgs
    Hashtable of build arguments
    
    .PARAMETER NoCache
    Whether to build without cache
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageName,
        
        [Parameter(Mandatory = $true)]
        [string]$ImageTag,
        
        [Parameter(Mandatory = $true)]
        [string]$DockerfilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$BuildContext,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$BuildArgs = @{},
        
        [Parameter(Mandatory = $false)]
        [switch]$NoCache
    )
    
    try {
        $fullImageName = "${ImageName}:${ImageTag}"
        
        Write-InfoLog "Building Docker image: $fullImageName" @{
            DockerfilePath = $DockerfilePath
            BuildContext = $BuildContext
            BuildArgs = ($BuildArgs.Keys -join ", ")
        }
        
        # Validate inputs
        if (-not (Test-Path $DockerfilePath)) {
            Write-CriticalLog "Dockerfile not found: $DockerfilePath"
        }
        
        if (-not (Test-Path $BuildContext)) {
            Write-CriticalLog "Build context directory not found: $BuildContext"
        }
        
        # Build docker command
        $dockerArgs = @(
            "build"
            "-f", $DockerfilePath
            "-t", $fullImageName
        )
        
        # Add build arguments
        foreach ($key in $BuildArgs.Keys) {
            $dockerArgs += @("--build-arg", "$key=$($BuildArgs[$key])")
        }
        
        # Add no-cache if specified
        if ($NoCache) {
            $dockerArgs += "--no-cache"
        }
        
        # Add build context
        $dockerArgs += $BuildContext
        
        # Execute build
        Write-InfoLog "Executing docker build command..."
        $buildOutput = & docker @dockerArgs 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog "Docker build output: $buildOutput"
            Write-CriticalLog "Docker build failed with exit code: $LASTEXITCODE"
        }
        
        Write-InfoLog "Docker image built successfully: $fullImageName"
        return $fullImageName
    }
    catch {
        Write-CriticalLog "Error building Docker image: $($_.Exception.Message)"
    }
}

function Test-DockerImage {
    <#
    .SYNOPSIS
    Tests if a Docker image exists locally
    
    .PARAMETER ImageName
    The full image name with tag
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageName
    )
    
    try {
        $result = docker images --format "{{.Repository}}:{{.Tag}}" $ImageName 2>$null
        return $result -eq $ImageName
    }
    catch {
        Write-ErrorLog "Error checking Docker image: $($_.Exception.Message)"
        return $false
    }
}

function Remove-DockerImage {
    <#
    .SYNOPSIS
    Removes a Docker image
    
    .PARAMETER ImageName
    The full image name with tag
    
    .PARAMETER Force
    Force removal of the image
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageName,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        Write-InfoLog "Removing Docker image: $ImageName"
        
        $dockerArgs = @("rmi")
        if ($Force) {
            $dockerArgs += "--force"
        }
        $dockerArgs += $ImageName
        
        $result = & docker @dockerArgs 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog "Failed to remove Docker image: $result"
            return $false
        }
        
        Write-InfoLog "Docker image removed successfully"
        return $true
    }
    catch {
        Write-ErrorLog "Error removing Docker image: $($_.Exception.Message)"
        return $false
    }
}

function Push-DockerImageToRegistry {
    <#
    .SYNOPSIS
    Pushes a Docker image to a registry
    
    .PARAMETER SourceImageName
    The local image name to push
    
    .PARAMETER TargetImageName
    The target image name in the registry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceImageName,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetImageName
    )
    
    try {
        Write-InfoLog "Pushing Docker image to registry..." @{
            Source = $SourceImageName
            Target = $TargetImageName
        }
        
        # Tag image for registry
        if ($SourceImageName -ne $TargetImageName) {
            Write-InfoLog "Tagging image: $SourceImageName -> $TargetImageName"
            $tagResult = docker tag $SourceImageName $TargetImageName 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                Write-CriticalLog "Failed to tag image: $tagResult"
            }
        }
        
        # Push image
        Write-InfoLog "Pushing image: $TargetImageName"
        $pushOutput = docker push $TargetImageName 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog "Docker push output: $pushOutput"
            Write-CriticalLog "Failed to push image to registry"
        }
        
        Write-InfoLog "Image pushed successfully to registry"
        return $true
    }
    catch {
        Write-CriticalLog "Error pushing Docker image: $($_.Exception.Message)"
    }
}

function Test-ContainerHealth {
    <#
    .SYNOPSIS
    Tests if a container is healthy and responsive
    
    .PARAMETER ContainerName
    The container name to test
    
    .PARAMETER MaxWaitSeconds
    Maximum time to wait for container to be healthy (default: 300)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxWaitSeconds = 300
    )
    
    try {
        Write-InfoLog "Testing container health: $ContainerName"
        
        $startTime = Get-Date
        $timeout = $startTime.AddSeconds($MaxWaitSeconds)
        
        do {
            $status = docker inspect $ContainerName --format "{{.State.Health.Status}}" 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                switch ($status) {
                    "healthy" {
                        Write-InfoLog "Container is healthy"
                        return $true
                    }
                    "unhealthy" {
                        Write-ErrorLog "Container is unhealthy"
                        return $false
                    }
                    "starting" {
                        Write-InfoLog "Container is starting, waiting..."
                        Start-Sleep -Seconds 5
                    }
                    default {
                        Write-InfoLog "Container health status: $status"
                        Start-Sleep -Seconds 5
                    }
                }
            } else {
                Write-ErrorLog "Failed to get container status"
                return $false
            }
        } while ((Get-Date) -lt $timeout)
        
        Write-ErrorLog "Container health check timed out"
        return $false
    }
    catch {
        Write-ErrorLog "Error testing container health: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function @(
    'Test-DockerInstallation',
    'Build-DockerImage',
    'Test-DockerImage',
    'Remove-DockerImage',
    'Push-DockerImageToRegistry',
    'Test-ContainerHealth'
)
