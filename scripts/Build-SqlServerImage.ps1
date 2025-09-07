# Build-SqlServerImage.ps1
# Builds a SQL Server Docker image with imported BACPAC files and migration script support

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Docker image name")]
    [string]$ImageName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Docker image tag")]
    [string]$ImageTag,
    
    [Parameter(Mandatory = $true, HelpMessage = "Array of local BACPAC file paths to import during build")]
    [string[]]$BacpacPaths,
    
    [Parameter(Mandatory = $false, HelpMessage = "Array of migration script file paths (mounted at runtime)")]
    [string[]]$MigrationScriptPaths = @(),
    
    [Parameter(Mandatory = $false, HelpMessage = "Array of database names corresponding to BACPAC files")]
    [string[]]$DatabaseNames = @(),
    
    [Parameter(Mandatory = $false, HelpMessage = "SQL Server SA password")]
    [SecureString]$SqlServerPassword,
    
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
    [switch]$SkipDockerValidation,
    
    [Parameter(Mandatory = $false, HelpMessage = "Migration scripts mount path in container (for documentation)")]
    [string]$MigrationMountPath = "/var/opt/mssql/migration-scripts"
)

# Import helper modules
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptDir\common\Logging-Helpers.ps1"
. "$scriptDir\common\Docker-Helpers.ps1"
. "$scriptDir\common\Azure-Helpers.ps1"

# Configure logging
Set-LogLevel $LogLevel
Set-LogPrefix "BUILD-IMAGE"

function Test-BacpacFiles {
    <#
    .SYNOPSIS
    Validates all BACPAC files exist and are readable
    #>
    param([string[]]$BacpacPaths)
    
    if ($BacpacPaths.Count -eq 0) {
        Write-CriticalLog "At least one BACPAC file is required"
    }
    
    Write-InfoLog "Validating $($BacpacPaths.Count) BACPAC file(s)..."
    
    foreach ($bacpacPath in $BacpacPaths) {
        if (-not (Test-Path $bacpacPath)) {
            Write-CriticalLog "BACPAC file not found: $bacpacPath"
        }
        
        if (-not $bacpacPath.EndsWith(".bacpac")) {
            Write-CriticalLog "File must be a .bacpac file: $bacpacPath"
        }
        
        # Validate file is readable and not empty
        try {
            $fileInfo = Get-Item $bacpacPath -ErrorAction Stop
            if ($fileInfo.Length -eq 0) {
                Write-CriticalLog "BACPAC file is empty: $bacpacPath"
            }
            
            $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
            Write-InfoLog "BACPAC validated: $bacpacPath ($fileSizeMB MB)"
        }
        catch {
            Write-CriticalLog "Cannot access BACPAC file: $bacpacPath - $($_.Exception.Message)"
        }
    }
    
    Write-InfoLog "BACPAC files validation completed"
    return $true
}

function Test-MigrationScripts {
    <#
    .SYNOPSIS
    Validates migration script files if provided
    #>
    param([string[]]$ScriptPaths)
    
    if ($ScriptPaths.Count -eq 0) {
        Write-InfoLog "No migration scripts provided - scripts can be mounted at runtime"
        return $true
    }
    
    Write-InfoLog "Validating $($ScriptPaths.Count) migration script(s)..."
    
    foreach ($scriptPath in $ScriptPaths) {
        if (-not (Test-Path $scriptPath)) {
            Write-CriticalLog "Migration script not found: $scriptPath"
        }
        
        if (-not $scriptPath.EndsWith(".sql")) {
            Write-CriticalLog "Migration script must be a .sql file: $scriptPath"
        }
        
        # Validate script is readable
        try {
            $content = Get-Content $scriptPath -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($content)) {
                Write-WarningLog "Migration script appears to be empty: $scriptPath"
            }
            else {
                Write-InfoLog "Migration script validated: $scriptPath"
            }
        }
        catch {
            Write-CriticalLog "Cannot read migration script: $scriptPath - $($_.Exception.Message)"
        }
    }
    
    Write-InfoLog "Migration scripts validation completed"
    return $true
}

function Get-DatabaseNames {
    <#
    .SYNOPSIS
    Generates database names from BACPAC files if not provided
    #>
    param([string[]]$BacpacPaths, [string[]]$ProvidedNames)
    
    $databaseNames = @()
    
    for ($i = 0; $i -lt $BacpacPaths.Count; $i++) {
        if ($i -lt $ProvidedNames.Count -and -not [string]::IsNullOrWhiteSpace($ProvidedNames[$i])) {
            $databaseNames += $ProvidedNames[$i]
        }
        else {
            # Generate name from BACPAC filename
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($BacpacPaths[$i])
            $dbName = $fileName -replace '[^a-zA-Z0-9_]', '_'
            $databaseNames += $dbName
        }
    }
    
    Write-InfoLog "Database names assigned:" 
    for ($i = 0; $i -lt $BacpacPaths.Count; $i++) {
        Write-InfoLog "  BACPAC: $(Split-Path $BacpacPaths[$i] -Leaf) -> Database: $($databaseNames[$i])"
    }
    
    return $databaseNames
}

function Resolve-MigrationScriptPaths {
    <#
    .SYNOPSIS
    Resolves wildcard patterns in migration script paths
    #>
    param([string[]]$ScriptPaths)
    
    $resolvedPaths = @()
    
    foreach ($path in $ScriptPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }
        
        Write-InfoLog "Processing migration script path: '$path'"
        
        if ($path -match '[\*\?]') {
            Write-InfoLog "Resolving wildcard pattern: $path"
            
            try {
                $matchedFiles = Get-ChildItem -Path $path -File | Where-Object { $_.Extension -eq '.sql' }
                Write-InfoLog "Found $($matchedFiles.Count) matching migration files"
                
                foreach ($file in $matchedFiles) {
                    $fullPath = $file.FullName
                    $resolvedPaths += $fullPath
                    Write-InfoLog "Resolved migration script: $fullPath"
                }
            }
            catch {
                Write-ErrorLog "Failed to resolve wildcard pattern '$path': $($_.Exception.Message)"
            }
        }
        else {
            if (Test-Path $path) {
                $fullPath = (Resolve-Path $path).Path
                $resolvedPaths += $fullPath
                Write-InfoLog "Direct migration script path: $fullPath"
            }
            else {
                Write-ErrorLog "Migration script file not found: $path"
            }
        }
    }
    
    Write-InfoLog "Resolved $($resolvedPaths.Count) migration script(s)"
    return ,$resolvedPaths
}

function New-BuildContext {
    <#
    .SYNOPSIS
    Creates the Docker build context with BACPAC files and migration scripts
    #>
    param(
        [string]$TempDir, 
        [string[]]$BacpacPaths, 
        [string[]]$DatabaseNames,
        [string[]]$MigrationScripts
    )
    
    Write-InfoLog "Creating multi-database build context in: $TempDir"
    
    # Resolve migration script paths
    $resolvedMigrationScripts = Resolve-MigrationScriptPaths -ScriptPaths $MigrationScripts
    
    # Create directory structure
    $bacpacDir = Join-Path $TempDir "bacpac-files"
    $migrationDir = Join-Path $TempDir "migration-scripts"
    
    New-Item -ItemType Directory -Force -Path $bacpacDir | Out-Null
    New-Item -ItemType Directory -Force -Path $migrationDir | Out-Null
    
    # Copy BACPAC files with database-specific naming
    Write-InfoLog "Copying $($BacpacPaths.Count) BACPAC file(s) for build-time import..."
    $bacpacManifest = @()
    
    for ($i = 0; $i -lt $BacpacPaths.Count; $i++) {
        $sourcePath = $BacpacPaths[$i]
        $dbName = $DatabaseNames[$i]
        $targetFileName = "$dbName.bacpac"
        $targetPath = Join-Path $bacpacDir $targetFileName
        
        Copy-Item $sourcePath $targetPath -Force
        
        $fileInfo = Get-Item $targetPath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        
        $bacpacManifest += @{
            SourceFile = Split-Path $sourcePath -Leaf
            TargetFile = $targetFileName
            DatabaseName = $dbName
            SizeMB = $fileSizeMB
        }
        
        Write-InfoLog "Copied BACPAC: $targetFileName ($fileSizeMB MB) -> Database: $dbName"
    }
    
    # Copy migration scripts for runtime mounting documentation
    if ($resolvedMigrationScripts.Count -gt 0) {
        Write-InfoLog "Copying $($resolvedMigrationScripts.Count) migration script(s) for reference..."
        Write-InfoLog "Note: Migration scripts will be mounted at runtime, not embedded in image"
        
        for ($i = 0; $i -lt $resolvedMigrationScripts.Count; $i++) {
            $script = $resolvedMigrationScripts[$i]            
            $fileName = "{0:D3}_{1}" -f ($i + 1), (Split-Path $script -Leaf)
            $destPath = Join-Path $migrationDir $fileName
            Copy-Item $script $destPath -Force
            Write-InfoLog "Copied migration script reference: $fileName"
        }
    }
    
    # Copy Docker files
    $dockerDir = Join-Path $scriptDir "..\docker"
    Copy-Item (Join-Path $dockerDir "*") $TempDir -Force
    Write-InfoLog "Copied Docker configuration files"
    
    # Create build manifest
    $buildManifest = @{
        ImageName = "$ImageName`:$ImageTag"
        BacpacFiles = $bacpacManifest
        MigrationScripts = $resolvedMigrationScripts.Count
        BuildTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
        MigrationMountPath = $MigrationMountPath
    }
    
    $manifestPath = Join-Path $TempDir "build-manifest.json"
    $buildManifest | ConvertTo-Json -Depth 3 | Set-Content $manifestPath
    Write-InfoLog "Created build manifest: $manifestPath"
    
    return @{
        BuildContext = $TempDir
        BacpacManifest = $bacpacManifest
        MigrationScriptCount = $resolvedMigrationScripts.Count
    }
}

function New-MultiDatabaseDockerfile {
    <#
    .SYNOPSIS
    Generates a Dockerfile for multi-database BACPAC import
    #>
    param([string]$TempDir, [hashtable[]]$BacpacManifest, [string]$MigrationMountPath)
    
    $dockerfilePath = Join-Path $TempDir "Dockerfile"
    
    $dockerfileContent = @"
# Multi-stage build for SQL Server with multiple BACPAC imports
FROM mcr.microsoft.com/mssql/server:2022-latest AS importer

# Install SqlPackage for BACPAC import
USER root
RUN apt-get update && apt-get install -y wget unzip && \
    wget -q https://aka.ms/sqlpackage-linux -O sqlpackage.zip && \
    unzip -q sqlpackage.zip -d /opt/sqlpackage && \
    chmod +x /opt/sqlpackage/sqlpackage && \
    rm sqlpackage.zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy BACPAC files
COPY bacpac-files/ /var/opt/mssql/bacpac/

# Set up SQL Server environment
ENV ACCEPT_EULA=Y
ENV MSSQL_PID=Developer

# Import script for multiple databases
RUN echo '#!/bin/bash' > /var/opt/mssql/import-databases.sh && \
    echo 'set -e' >> /var/opt/mssql/import-databases.sh && \
    echo '/opt/mssql/bin/sqlservr &' >> /var/opt/mssql/import-databases.sh && \
    echo 'SERVER_PID=$$!' >> /var/opt/mssql/import-databases.sh && \
    echo 'echo "Waiting for SQL Server to start..."' >> /var/opt/mssql/import-databases.sh && \
    echo 'sleep 30' >> /var/opt/mssql/import-databases.sh && \
    echo '' >> /var/opt/mssql/import-databases.sh
"@

    # Add import commands for each BACPAC
    foreach ($bacpac in $BacpacManifest) {
        $dockerfileContent += @"
    echo 'echo "Importing $($bacpac.DatabaseName) from $($bacpac.TargetFile)..."' >> /var/opt/mssql/import-databases.sh && \
    echo '/opt/sqlpackage/sqlpackage /Action:Import /SourceFile:/var/opt/mssql/bacpac/$($bacpac.TargetFile) /TargetServerName:localhost /TargetDatabaseName:$($bacpac.DatabaseName) /TargetUser:sa /TargetPassword:$$SA_PASSWORD /ua:True' >> /var/opt/mssql/import-databases.sh && \
    echo 'echo "Import completed for $($bacpac.DatabaseName)"' >> /var/opt/mssql/import-databases.sh && \
    echo '' >> /var/opt/mssql/import-databases.sh
"@
    }

    $dockerfileContent += @"
    echo 'echo "All databases imported successfully"' >> /var/opt/mssql/import-databases.sh && \
    echo 'kill $$SERVER_PID' >> /var/opt/mssql/import-databases.sh && \
    echo 'wait $$SERVER_PID' >> /var/opt/mssql/import-databases.sh && \
    chmod +x /var/opt/mssql/import-databases.sh

# Run the import process during build
ARG SA_PASSWORD
RUN /var/opt/mssql/import-databases.sh

# Final runtime image
FROM mcr.microsoft.com/mssql/server:2022-latest

# Copy imported databases from build stage
COPY --from=importer /var/opt/mssql/data/ /var/opt/mssql/data/

# Create migration scripts directory for runtime mounting
RUN mkdir -p $MigrationMountPath

# Set up runtime environment
ENV ACCEPT_EULA=Y
ENV MSSQL_PID=Developer

# Runtime startup script that can execute migration scripts
COPY startup.sh /var/opt/mssql/startup.sh
RUN chmod +x /var/opt/mssql/startup.sh

# Expose SQL Server port
EXPOSE 1433

# Use custom startup script
CMD ["/var/opt/mssql/startup.sh"]
"@

    Set-Content -Path $dockerfilePath -Value $dockerfileContent
    Write-InfoLog "Generated multi-database Dockerfile: $dockerfilePath"
    
    # Create startup script for runtime migration execution
    $startupScriptPath = Join-Path $TempDir "startup.sh"
    $startupScript = @"
#!/bin/bash
set -e

echo "Starting SQL Server with imported databases..."

# Start SQL Server in background
/opt/mssql/bin/sqlservr &
SERVER_PID=`$!

# Wait for SQL Server to be ready
echo "Waiting for SQL Server to start..."
sleep 30

# Execute migration scripts if mounted
if [ -d "$MigrationMountPath" ] && [ "`$(ls -A $MigrationMountPath 2>/dev/null)" ]; then
    echo "Found migration scripts in $MigrationMountPath"
    for script in $MigrationMountPath/*.sql; do
        if [ -f "`$script" ]; then
            echo "Executing migration script: `$(basename `$script)"
            /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "`$SA_PASSWORD" -i "`$script"
        fi
    done
    echo "Migration scripts execution completed"
else
    echo "No migration scripts found in $MigrationMountPath (mount scripts as volume for runtime execution)"
fi

echo "SQL Server is ready for connections"

# Keep SQL Server running
wait `$SERVER_PID
"@

    Set-Content -Path $startupScriptPath -Value $startupScript
    Write-InfoLog "Generated runtime startup script: $startupScriptPath"
    
    return $dockerfilePath
}

function main {
    try {
        # Convert SecureString password to plain text for Docker build
        $plainPassword = if ($SqlServerPassword) {
            [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlServerPassword))
        } else {
            "YourStrong@Passw0rd123"  # Default password
        }
        
        Write-InfoLog "=== Multi-Database SQL Server Image Build Started ===" @{
            ImageName = $ImageName
            ImageTag = $ImageTag
            BacpacCount = $BacpacPaths.Count
            MigrationScripts = $MigrationScriptPaths.Count
            LogLevel = $LogLevel
            BuildProcess = "Multi-stage with multiple BACPAC imports"
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
        
        # Validate files
        Test-BacpacFiles -BacpacPaths $BacpacPaths
        Test-MigrationScripts -ScriptPaths $MigrationScriptPaths
        
        # Generate database names
        $databaseNames = Get-DatabaseNames -BacpacPaths $BacpacPaths -ProvidedNames $DatabaseNames
        
        # Setup temporary directory
        if (-not $TempDirectory) {
            $TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "sql-image-build-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }
        
        if (Test-Path $TempDirectory) {
            Remove-Item $TempDirectory -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $TempDirectory | Out-Null
        
        Write-InfoLog "Using temporary directory: $TempDirectory"
        
        try {
            # Create build context
            $buildResult = New-BuildContext -TempDir $TempDirectory -BacpacPaths $BacpacPaths -DatabaseNames $databaseNames -MigrationScripts $MigrationScriptPaths
            
            # Generate Dockerfile for multi-database setup
            $dockerfilePath = New-MultiDatabaseDockerfile -TempDir $TempDirectory -BacpacManifest $buildResult.BacpacManifest -MigrationMountPath $MigrationMountPath
            
            # Prepare build arguments
            $dockerBuildArgs = @{
                "SA_PASSWORD" = $plainPassword
            }
            
            # Add custom build args
            foreach ($key in $BuildArgs.Keys) {
                $dockerBuildArgs[$key] = $BuildArgs[$key]
            }
            
            Write-InfoLog "Starting multi-database Docker build..."
            Write-InfoLog "BACPAC files will be imported during build (not in final image)"
            Write-InfoLog "Migration scripts should be mounted at runtime: $MigrationMountPath"
            
            # Build Docker image
            $fullImageName = Build-DockerImage -ImageName $ImageName -ImageTag $ImageTag -DockerfilePath $dockerfilePath -BuildContext $TempDirectory -BuildArgs $dockerBuildArgs -NoCache:$NoCache
            
            # Test the built image
            Write-InfoLog "Testing built image..."
            if (-not (Test-DockerImage -ImageName $fullImageName)) {
                Write-CriticalLog "Built image verification failed"
            }
            
            # Get final image information
            $imageInspect = docker inspect $fullImageName --format "{{.Size}}" 2>$null
            $imageSizeMB = if ($imageInspect) { [math]::Round([long]$imageInspect / 1MB, 2) } else { "Unknown" }
            
            Write-InfoLog "=== Multi-Database SQL Server Image Build Completed Successfully ===" @{
                ImageName = $fullImageName
                DatabaseCount = $databaseNames.Count
                MigrationScripts = $buildResult.MigrationScriptCount
                FinalImageSizeMB = $imageSizeMB
                MigrationMountPath = $MigrationMountPath
            }
            
            # Output results
            Write-Host "##[section]Build Results"
            Write-Host "CONTAINER_IMAGE=$fullImageName"
            Write-Host "IMAGE_NAME=$ImageName"
            Write-Host "IMAGE_TAG=$ImageTag"
            Write-Host "DATABASE_COUNT=$($databaseNames.Count)"
            Write-Host "DATABASES=$($databaseNames -join ',')"
            Write-Host "MIGRATION_SCRIPTS_COUNT=$($buildResult.MigrationScriptCount)"
            Write-Host "MIGRATION_MOUNT_PATH=$MigrationMountPath"
            Write-Host "FINAL_IMAGE_SIZE_MB=$imageSizeMB"
            Write-Host "BACPAC_IN_FINAL_IMAGE=FALSE"
            
            # Output usage instructions
            Write-Host ""
            Write-Host "##[section]Usage Instructions"
            Write-Host "To run with migration scripts:"
            Write-Host "docker run -d -p 1433:1433 -e SA_PASSWORD='[YourPassword]' -v /path/to/migration-scripts:$MigrationMountPath $fullImageName"
            
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
        Write-CriticalLog "Unhandled error in image build: $($_.Exception.Message)"
        exit 1
    }
}

# Execute main function
main
