# Build-SqlContainer.ps1
# [DEPRECATED] This script has been split into modular components for better maintainability
# Use Download-FileFromBlobStorage.ps1 and Build-SqlServerImage.ps1 instead
#
# Legacy: Builds a SQL Server container with imported BACPAC and executes migration scripts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to BACPAC file or download URL")]
    [string]$BacpacPath,
    
    [Parameter(Mandatory = $true, HelpMessage = "Docker image name")]
    [string]$ImageName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Docker image tag")]
    [string]$ImageTag,
    
    [Parameter(Mandatory = $false, HelpMessage = "Array of migration script file paths")]
    [string[]]$MigrationScriptPaths = @(),
    
    [Parameter(Mandatory = $false, HelpMessage = "SQL Server SA password")]
    [string]$SqlServerPassword = "YourStrong@Passw0rd123",
    
    [Parameter(Mandatory = $false, HelpMessage = "Database name after import")]
    [string]$DatabaseName = "ImportedDatabase",
    
    [Parameter(Mandatory = $false, HelpMessage = "Additional Docker build arguments")]
    [hashtable]$BuildArgs = @{},
    
    [Parameter(Mandatory = $false, HelpMessage = "Build without cache")]
    [switch]$NoCache,
    
    [Parameter(Mandatory = $false, HelpMessage = "Log level (Debug, Info, Warning, Error, Critical)")]
    [ValidateSet("Debug", "Info", "Warning", "Error", "Critical")]
    [string]$LogLevel = "Info",
    
    [Parameter(Mandatory = $false, HelpMessage = "Temporary directory for build context")]
    [string]$TempDirectory = $null,
    
    [Parameter(Mandatory = $false, HelpMessage = "Skip Docker installation validation")]
    [switch]$SkipDockerValidation
)

# Import helper modules
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptDir\common\Logging-Helpers.ps1"
. "$scriptDir\common\Docker-Helpers.ps1"
. "$scriptDir\common\Azure-Helpers.ps1"

# Configure logging
Set-LogLevel $LogLevel
Set-LogPrefix "BUILD-CONTAINER"

function Test-ScriptFiles {
    param([string[]]$ScriptPaths, [string]$ScriptType)
    
    if ($ScriptPaths.Count -eq 0) {
        Write-InfoLog "No $ScriptType scripts provided"
        return $true
    }
    
    Write-InfoLog "Validating $($ScriptPaths.Count) $ScriptType script(s)..."
    
    foreach ($scriptPath in $ScriptPaths) {
        if (-not (Test-Path $scriptPath)) {
            Write-CriticalLog "$ScriptType script not found: $scriptPath"
        }
        
        if (-not $scriptPath.EndsWith(".sql")) {
            Write-CriticalLog "$ScriptType script must be a .sql file: $scriptPath"
        }
        
        # Validate script is readable
        try {
            $content = Get-Content $scriptPath -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($content)) {
                Write-WarningLog "$ScriptType script appears to be empty: $scriptPath"
            }
        }
        catch {
            Write-CriticalLog "Cannot read $ScriptType script: $scriptPath - $($_.Exception.Message)"
        }
    }
    
    Write-InfoLog "$ScriptType scripts validation completed"
    return $true
}

function Get-BacpacFile {
    param([string]$BacpacPath, [string]$TempDir)
    
    if ($BacpacPath -match "^https?://") {
        # Download from URL
        $bacpacFileName = Split-Path $BacpacPath -Leaf
        if (-not $bacpacFileName.EndsWith(".bacpac")) {
            $bacpacFileName = "database.bacpac"
        }
        
        $localBacpacPath = Join-Path $TempDir $bacpacFileName
        
        Write-InfoLog "Downloading BACPAC from URL..." @{
            Url = $BacpacPath
            LocalPath = $localBacpacPath
        }
        
        try {
            # Check if this is an Azure blob URL
            if ($BacpacPath -match "https://([^.]+)\.blob\.core\.windows\.net/") {
                Write-InfoLog "Detected Azure Blob Storage URL, using Azure CLI authentication..."
                $downloadSuccess = Download-BacpacFromStorage -BlobUrl $BacpacPath -LocalPath $localBacpacPath
                if (-not $downloadSuccess) {
                    Write-CriticalLog "Failed to download BACPAC from Azure Blob Storage"
                }
            }
            else {
                # Use PowerShell WebClient for non-Azure URLs
                Write-InfoLog "Using standard HTTP download..."
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($BacpacPath, $localBacpacPath)
                $webClient.Dispose()
            }
        }
        catch {
            Write-CriticalLog "Failed to download BACPAC file: $($_.Exception.Message)"
        }
        
        return $localBacpacPath
    }
    else {
        # Use local file
        if (-not (Test-Path $BacpacPath)) {
            Write-CriticalLog "BACPAC file not found: $BacpacPath"
        }
        
        return $BacpacPath
    }
}

function Resolve-ScriptPaths {
    <#
    .SYNOPSIS
    Resolves wildcard patterns in script paths to actual file paths
    #>
    param(
        [string[]]$ScriptPaths
    )
    
    $resolvedPaths = @()
    
    foreach ($path in $ScriptPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }
        
        Write-InfoLog "Processing script path: '$path'"
        
        # Check if path contains wildcards
        if ($path -match '[\*\?]') {
            Write-InfoLog "Resolving wildcard pattern: $path"
            
            # Resolve wildcards using Get-ChildItem
            try {
                $matchedFiles = Get-ChildItem -Path $path -File | Where-Object { $_.Extension -eq '.sql' }
                Write-InfoLog "Found $($matchedFiles.Count) matching files"
                
                foreach ($file in $matchedFiles) {
                    $fullPath = $file.FullName
                    $resolvedPaths += $fullPath
                    Write-InfoLog "Resolved to: $fullPath"
                }
            }
            catch {
                Write-ErrorLog "Failed to resolve wildcard pattern '$path': $($_.Exception.Message)"
            }
        }
        else {
            # Direct path, just add it
            if (Test-Path $path) {
                $fullPath = (Resolve-Path $path).Path
                $resolvedPaths += $fullPath
                Write-InfoLog "Direct path resolved: $fullPath"
            }
            else {
                Write-ErrorLog "Script file not found: $path"
            }
        }
    }
    
    Write-InfoLog "Final resolved paths count: $($resolvedPaths.Count)"
    for ($i = 0; $i -lt $resolvedPaths.Count; $i++) {
        Write-InfoLog "  [$i]: '$($resolvedPaths[$i])'"
    }
    
    # forces the result to be array even when 1 entry is returned.
    return ,$resolvedPaths
}

function New-BuildContext {
    param([string]$TempDir, [string]$BacpacPath, [string[]]$MigrationScripts)
    
    Write-InfoLog "Creating build context in: $TempDir"
    
    # Resolve wildcard patterns in script paths
    $resolvedMigrationScripts = Resolve-ScriptPaths -ScriptPaths $MigrationScripts
    
    Write-InfoLog "Resolved $($resolvedMigrationScripts.Count) migration script(s) from $($MigrationScripts.Count) pattern(s)"
    
    # Create directory structure
    $sqlScriptsDir = Join-Path $TempDir "sql-scripts"
    $migrationDir = Join-Path $sqlScriptsDir "migrations"
    
    New-Item -ItemType Directory -Force -Path $sqlScriptsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $migrationDir | Out-Null
    
    # Copy BACPAC file (will be imported during build, not included in final image)
    $buildBacpacPath = Join-Path $TempDir "database.bacpac"
    Copy-Item $BacpacPath $buildBacpacPath -Force
    Write-InfoLog "Copied BACPAC file to build context (will be imported during build)"
    
    # Copy migration scripts
    if ($resolvedMigrationScripts.Count -gt 0) {
        Write-InfoLog "Copying $($resolvedMigrationScripts.Count) migration script(s)..."
        for ($i = 0; $i -lt $resolvedMigrationScripts.Count; $i++) {
            $script = $resolvedMigrationScripts[$i]            
            $fileName = "{0:D3}_{1}" -f ($i + 1), (Split-Path $script -Leaf)
            $destPath = Join-Path $migrationDir $fileName
            Copy-Item $script $destPath -Force
            Write-InfoLog "Copied migration script: $fileName"
        }
    }
    
    # Copy Docker files
    $dockerDir = Join-Path $scriptDir "..\docker"
    Copy-Item (Join-Path $dockerDir "*") $TempDir -Force
    Write-InfoLog "Copied Docker configuration files"
    
    return $TempDir
}

function main {
    try {
        Write-WarningLog "=== DEPRECATION NOTICE ==="
        Write-WarningLog "This script has been split into modular components:"
        Write-WarningLog "1. Download-FileFromBlobStorage.ps1 - For downloading files from Azure Blob Storage"
        Write-WarningLog "2. Build-SqlServerImage.ps1 - For building Docker images with multiple BACPAC files"
        Write-WarningLog "Consider using the new modular scripts for better maintainability and flexibility"
        Write-WarningLog "==============================="
        Write-WarningLog ""
        
        Write-InfoLog "=== SQL Container Build Started (Legacy Mode) ===" @{
            ImageName = $ImageName
            ImageTag = $ImageTag
            BacpacPath = $BacpacPath
            MigrationScripts = $MigrationScriptPaths.Count
            DatabaseName = $DatabaseName
            BuildProcess = "Multi-stage with BACPAC import during build"
            LogLevel = $LogLevel
        }
        
        # Validate prerequisites
        Write-InfoLog "Validating prerequisites..."
        
        if (-not $SkipDockerValidation) {
            if (-not (Test-DockerInstallation)) {
                Write-CriticalLog "Docker installation validation failed"
            }
        } else {
            Write-InfoLog "Skipping Docker validation as requested"
        }
        
        # Validate script files
        Test-ScriptFiles -ScriptPaths $MigrationScriptPaths -ScriptType "Migration"
        
        # Setup temporary directory
        if (-not $TempDirectory) {
            $TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "sql-container-build-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }
        
        if (Test-Path $TempDirectory) {
            Remove-Item $TempDirectory -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $TempDirectory | Out-Null
        
        Write-InfoLog "Using temporary directory: $TempDirectory"
        
        try {
            # Get BACPAC file (download if URL)
            $localBacpacPath = Get-BacpacFile -BacpacPath $BacpacPath -TempDir $TempDirectory
            
            # Validate BACPAC file
            $bacpacSize = (Get-Item $localBacpacPath).Length
            Write-InfoLog "BACPAC file size: $([math]::Round($bacpacSize / 1MB, 2)) MB (will be imported during build)"
            
            # Create build context
            $buildContext = New-BuildContext -TempDir $TempDirectory -BacpacPath $localBacpacPath -MigrationScripts $MigrationScriptPaths
            
            # Prepare build arguments
            $dockerBuildArgs = @{
                "SA_PASSWORD" = $SqlServerPassword
                "DATABASE_NAME" = $DatabaseName
                "BACPAC_FILE" = "database.bacpac"
            }
            
            # Add custom build args
            foreach ($key in $BuildArgs.Keys) {
                $dockerBuildArgs[$key] = $BuildArgs[$key]
            }
            
            Write-InfoLog "Starting multi-stage Docker build with BACPAC import..."
            Write-InfoLog "Note: BACPAC will be imported during build and NOT included in final image"
            
            # Build Docker image with multi-stage process
            $dockerfilePath = Join-Path $buildContext "Dockerfile"
            $fullImageName = Build-DockerImage -ImageName $ImageName -ImageTag $ImageTag -DockerfilePath $dockerfilePath -BuildContext $buildContext -BuildArgs $dockerBuildArgs -NoCache:$NoCache
            
            # Test the built image
            Write-InfoLog "Testing built image..."
            if (-not (Test-DockerImage -ImageName $fullImageName)) {
                Write-CriticalLog "Built image verification failed"
            }
            
            # Verify final image size (should be smaller without BACPAC)
            $imageInspect = docker inspect $fullImageName --format "{{.Size}}" 2>$null
            if ($imageInspect) {
                $imageSizeMB = [math]::Round([long]$imageInspect / 1MB, 2)
                Write-InfoLog "Final image size: $imageSizeMB MB (excludes BACPAC file)"
            }
            
            Write-InfoLog "=== SQL Container Build Completed Successfully ===" @{
                ImageName = $fullImageName
                BuildContext = $buildContext
                TotalScripts = $MigrationScriptPaths.Count
                BacpacImported = "During build stage"
                FinalImageSizeMB = if ($imageInspect) { $imageSizeMB } else { "Unknown" }
            }
            
            # Output key information for CI/CD systems
            Write-Host "##[section]Build Results"
            Write-Host "CONTAINER_IMAGE=$fullImageName"
            Write-Host "IMAGE_NAME=$ImageName"
            Write-Host "IMAGE_TAG=$ImageTag"
            Write-Host "DATABASE_NAME=$DatabaseName"
            Write-Host "MIGRATION_SCRIPTS_COUNT=$($MigrationScriptPaths.Count)"
            Write-Host "BACPAC_IMPORTED_DURING=BUILD_STAGE"
            Write-Host "BACPAC_IN_FINAL_IMAGE=FALSE"
            if ($imageInspect) {
                Write-Host "FINAL_IMAGE_SIZE_MB=$imageSizeMB"
            }
            
            exit 0
        }
        finally {
            # Cleanup temporary directory
            if (Test-Path $TempDirectory) {
                Write-InfoLog "Cleaning up temporary directory: $TempDirectory"
                Remove-Item $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-CriticalLog "Unhandled error in container build: $($_.Exception.Message)"
        exit 1
    }
}

# Execute main function
main
