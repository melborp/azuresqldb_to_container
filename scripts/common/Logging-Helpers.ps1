# Logging-Helpers.ps1
# Provides structured logging functionality for CI/CD integration

enum LogLevel {
    Debug = 0
    Info = 1
    Warning = 2
    Error = 3
    Critical = 4
}

# Simple logging implementation without classes for better compatibility
$Global:LoggerConfig = @{
    MinimumLevel = [LogLevel]::Info
    LogPrefix = ""
}

function Write-Log {
    param(
        [LogLevel]$Level,
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    
    if ($Level -ge $Global:LoggerConfig.MinimumLevel) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $levelName = $Level.ToString().ToUpper()
        
        # Format for CI/CD systems
        $logEntry = "[$timestamp] [$levelName]"
        if ($Global:LoggerConfig.LogPrefix) {
            $logEntry += " [$($Global:LoggerConfig.LogPrefix)]"
        }
        $logEntry += " $Message"
        
        # Add properties if provided
        if ($Properties.Count -gt 0) {
            $propsJson = $Properties | ConvertTo-Json -Compress
            $logEntry += " | Properties: $propsJson"
        }
        
        # Output to appropriate stream based on level
        switch ($Level) {
            ([LogLevel]::Debug) { Write-Debug $logEntry }
            ([LogLevel]::Info) { Write-Host $logEntry -ForegroundColor Green }
            ([LogLevel]::Warning) { Write-Warning $logEntry }
            ([LogLevel]::Error) { Write-Error $logEntry }
            ([LogLevel]::Critical) { Write-Error $logEntry }
        }
    }
}

function Set-LogLevel {
    param([LogLevel]$Level)
    $Global:LoggerConfig.MinimumLevel = $Level
}

function Set-LogPrefix {
    param([string]$Prefix)
    $Global:LoggerConfig.LogPrefix = $Prefix
}

function Write-InfoLog {
    param(
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    Write-Log -Level ([LogLevel]::Info) -Message $Message -Properties $Properties
}

function Write-WarningLog {
    param(
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    Write-Log -Level ([LogLevel]::Warning) -Message $Message -Properties $Properties
}

function Write-ErrorLog {
    param(
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    Write-Log -Level ([LogLevel]::Error) -Message $Message -Properties $Properties
}

function Write-CriticalLog {
    param(
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    Write-Log -Level ([LogLevel]::Critical) -Message $Message -Properties $Properties
    throw $Message
}

function Write-DebugLog {
    param(
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    Write-Log -Level ([LogLevel]::Debug) -Message $Message -Properties $Properties
}
