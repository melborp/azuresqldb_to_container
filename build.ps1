# build.ps1
# Main orchestrator script for the entire BACPAC to Container process

[CmdletBinding()]
param(
    # Export Parameters
    [Parameter(Mandatory = $false, HelpMessage = "Azure subscription ID")]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false, HelpMessage = "Resource group containing the SQL server")]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false, HelpMessage = "SQL server name")]
    [string]$ServerName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Database name to export")]
    [string]$DatabaseName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Storage account name for BACPAC storage")]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Storage container name")]
    [string]$ContainerName,
    
    [Parameter(Mandatory = $false, HelpMessage = "BACPAC file name")]
    [string]$BacpacFileName,
    
    [Parameter(Mandatory = $false, HelpMessage = "SQL server admin username")]
    [string]$AdminUser,
    
    [Parameter(Mandatory = $false, HelpMessage = "SQL server admin password")]
    [string]$AdminPassword,
    
    # Build Parameters
    [Parameter(Mandatory = $false, HelpMessage = "Path to BACPAC file or download URL (if not exporting)")]
    [string]$BacpacPath,
    
    [Parameter(Mandatory = $true, HelpMessage = "Docker image name")]
    [string]$ImageName,
    
    [Parameter(Mandatory = $true, HelpMessage = "Docker image tag")]
    [string]$ImageTag,
    
    [Parameter(Mandatory = $false, HelpMessage = "Array of migration script file paths")]
    [string[]]$MigrationScriptPaths = @(),
    
    [Parameter(Mandatory = $false, HelpMessage = "Array of upgrade script file paths")]
    [string[]]$UpgradeScriptPaths = @(),
    
    [Parameter(Mandatory = $false, HelpMessage = "SQL Server SA password")]
    [string]$SqlServerPassword = "YourStrong@Passw0rd123",
    
    [Parameter(Mandatory = $false, HelpMessage = "Database name after import")]
    [string]$ImportedDatabaseName = "ImportedDatabase",
    
    # Push Parameters
    [Parameter(Mandatory = $false, HelpMessage = "Azure Container Registry name")]
    [string]$RegistryName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Additional tags to apply")]
    [string[]]$AdditionalTags = @(),
    
    # Control Parameters
    [Parameter(Mandatory = $false, HelpMessage = "Skip database export step")]
    [switch]$SkipExport,
    
    [Parameter(Mandatory = $false, HelpMessage = "Skip container build step")]
    [switch]$SkipBuild,
    
    [Parameter(Mandatory = $false, HelpMessage = "Skip container push step")]
    [switch]$SkipPush,
    
    [Parameter(Mandatory = $false, HelpMessage = "Build without cache")]
    [switch]$NoCache,
    
    [Parameter(Mandatory = $false, HelpMessage = "Log level (Debug, Info, Warning, Error, Critical)")]
    [ValidateSet("Debug", "Info", "Warning", "Error", "Critical")]
    [string]$LogLevel = "Info",
    
    [Parameter(Mandatory = $false, HelpMessage = "Skip Docker installation validation")]
    [switch]$SkipDockerValidation
)

# Import helper modules
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptsDir = Join-Path $scriptDir "scripts"
. "$scriptsDir\common\Logging-Helpers.ps1"

# Configure logging
Set-LogLevel $LogLevel
Set-LogPrefix "ORCHESTRATOR"

function Test-Prerequisites {
    Write-InfoLog "Testing prerequisites..."
    
    # Test PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-WarningLog "PowerShell 7.x+ is recommended. Current version: $($PSVersionTable.PSVersion)"
    }
    
    # Test if scripts exist
    $requiredScripts = @(
        "Export-AzureSqlDatabase.ps1",
        "Build-SqlContainer.ps1", 
        "Push-ContainerImage.ps1"
    )
    
    foreach ($script in $requiredScripts) {
        $scriptPath = Join-Path $scriptsDir $script
        if (-not (Test-Path $scriptPath)) {
            Write-CriticalLog "Required script not found: $scriptPath"
        }
    }
    
    Write-InfoLog "Prerequisites check completed"
}

function Invoke-DatabaseExport {
    Write-InfoLog "=== Step 1: Database Export ==="
    
    # Validate required parameters for export
    $requiredParams = @{
        'SubscriptionId' = $SubscriptionId
        'ResourceGroupName' = $ResourceGroupName
        'ServerName' = $ServerName
        'DatabaseName' = $DatabaseName
        'StorageAccountName' = $StorageAccountName
        'ContainerName' = $ContainerName
        'BacpacFileName' = $BacpacFileName
    }
    
    foreach ($param in $requiredParams.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace($param.Value)) {
            Write-CriticalLog "Required parameter for export is missing: $($param.Key)"
        }
    }
    
    # Build export command
    $exportScript = Join-Path $scriptsDir "Export-AzureSqlDatabase.ps1"
    $exportArgs = @(
        "-SubscriptionId", $SubscriptionId
        "-ResourceGroupName", $ResourceGroupName
        "-ServerName", $ServerName
        "-DatabaseName", $DatabaseName
        "-StorageAccountName", $StorageAccountName
        "-ContainerName", $ContainerName
        "-BacpacFileName", $BacpacFileName
        "-LogLevel", $LogLevel
    )
    
    if ($AdminUser) {
        $exportArgs += @("-AdminUser", $AdminUser)
    }
    
    if ($AdminPassword) {
        $exportArgs += @("-AdminPassword", $AdminPassword)
    }
    
    # Execute export
    Write-InfoLog "Executing database export script..."
    & $exportScript @exportArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-CriticalLog "Database export failed with exit code: $LASTEXITCODE"
    }
    
    # Set BACPAC path for next step
    $script:BacpacPath = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BacpacFileName"
    Write-InfoLog "Export completed. BACPAC available at: $script:BacpacPath"
}

function Invoke-ContainerBuild {
    Write-InfoLog "=== Step 2: Container Build ==="
    
    # Determine BACPAC source
    $bacpacSource = if ($script:BacpacPath) { $script:BacpacPath } else { $BacpacPath }
    
    if ([string]::IsNullOrWhiteSpace($bacpacSource)) {
        Write-CriticalLog "No BACPAC source specified. Either export a database or provide BacpacPath parameter."
    }
    
    # Build container command
    $buildScript = Join-Path $scriptsDir "Build-SqlContainer.ps1"
    
    # Build parameter hashtable for explicit binding
    $buildParams = @{
        BacpacPath = $bacpacSource
        ImageName = $ImageName
        ImageTag = $ImageTag
        SqlServerPassword = $SqlServerPassword
        DatabaseName = $ImportedDatabaseName
        LogLevel = $LogLevel
        SkipDockerValidation = $SkipDockerValidation
    }
    
    if ($MigrationScriptPaths.Count -gt 0) {
        $buildParams.MigrationScriptPaths = $MigrationScriptPaths
    }
    
    if ($UpgradeScriptPaths.Count -gt 0) {
        $buildParams.UpgradeScriptPaths = $UpgradeScriptPaths
    }
    
    if ($NoCache) {
        $buildParams.NoCache = $true
    }
    
    # Execute build
    Write-InfoLog "Executing container build script..."
    & $buildScript @buildParams
    
    if ($LASTEXITCODE -ne 0) {
        Write-CriticalLog "Container build failed with exit code: $LASTEXITCODE"
    }
    
    Write-InfoLog "Container build completed successfully"
}

function Invoke-ContainerPush {
    Write-InfoLog "=== Step 3: Container Push ==="
    
    if ([string]::IsNullOrWhiteSpace($RegistryName)) {
        Write-CriticalLog "RegistryName is required for push operation"
    }
    
    # Build push command
    $pushScript = Join-Path $scriptsDir "Push-ContainerImage.ps1"
    $pushArgs = @(
        "-RegistryName", $RegistryName
        "-ImageName", $ImageName
        "-ImageTag", $ImageTag
        "-LogLevel", $LogLevel
    )
    
    if ($SubscriptionId) {
        $pushArgs += @("-SubscriptionId", $SubscriptionId)
    }
    
    if ($AdditionalTags.Count -gt 0) {
        $pushArgs += @("-AdditionalTags", $AdditionalTags)
    }
    
    # Execute push
    Write-InfoLog "Executing container push script..."
    & $pushScript @pushArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-CriticalLog "Container push failed with exit code: $LASTEXITCODE"
    }
    
    Write-InfoLog "Container push completed successfully"
}

function main {
    try {
        $startTime = Get-Date
        
        Write-InfoLog "=== BACPAC to Container Orchestrator Started ===" @{
            ImageName = $ImageName
            ImageTag = $ImageTag
            SkipExport = $SkipExport.IsPresent
            SkipBuild = $SkipBuild.IsPresent
            SkipPush = $SkipPush.IsPresent
            MigrationScripts = $MigrationScriptPaths.Count
            UpgradeScripts = $UpgradeScriptPaths.Count
        }
        
        # Test prerequisites
        Test-Prerequisites
        
        # Execute steps based on flags
        if (-not $SkipExport) {
            Invoke-DatabaseExport
        } else {
            Write-InfoLog "Skipping database export as requested"
            $script:BacpacPath = $BacpacPath
        }
        
        if (-not $SkipBuild) {
            Invoke-ContainerBuild
        } else {
            Write-InfoLog "Skipping container build as requested"
        }
        
        if (-not $SkipPush) {
            Invoke-ContainerPush
        } else {
            Write-InfoLog "Skipping container push as requested"
        }
        
        $duration = (Get-Date) - $startTime
        
        Write-InfoLog "=== BACPAC to Container Process Completed Successfully ===" @{
            TotalDuration = $duration.ToString("hh\:mm\:ss")
            FinalImage = if ($RegistryName) { "$RegistryName.azurecr.io/${ImageName}:${ImageTag}" } else { "${ImageName}:${ImageTag}" }
        }
        
        # Output summary for CI/CD
        Write-Host "##[section]Process Summary"
        Write-Host "PROCESS_DURATION=$($duration.ToString("hh\:mm\:ss"))"
        Write-Host "FINAL_IMAGE=${ImageName}:${ImageTag}"
        if ($RegistryName) {
            Write-Host "REGISTRY_IMAGE=$RegistryName.azurecr.io/${ImageName}:${ImageTag}"
        }
        
        exit 0
    }
    catch {
        Write-CriticalLog "Unhandled error in orchestrator: $($_.Exception.Message)"
        exit 1
    }
}

# Execute main function
main
