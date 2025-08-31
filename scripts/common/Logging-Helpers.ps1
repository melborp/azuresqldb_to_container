# Logging-Helpers.ps1
# Provides structured logging functionality for CI/CD integration

enum LogLevel {
    Debug = 0
    Info = 1
    Warning = 2
    Error = 3
    Critical = 4
}

class Logger {
    [LogLevel]$MinimumLevel
    [string]$LogPrefix
    
    Logger([LogLevel]$minimumLevel = [LogLevel]::Info, [string]$logPrefix = "") {
        $this.MinimumLevel = $minimumLevel
        $this.LogPrefix = $logPrefix
    }
    
    [void] WriteLog([LogLevel]$level, [string]$message, [hashtable]$properties = @{}) {
        if ($level -ge $this.MinimumLevel) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            $levelName = $level.ToString().ToUpper()
            
            # Format for CI/CD systems
            $logEntry = "[$timestamp] [$levelName]"
            if ($this.LogPrefix) {
                $logEntry += " [$($this.LogPrefix)]"
            }
            $logEntry += " $message"
            
            # Add properties if provided
            if ($properties.Count -gt 0) {
                $propsJson = $properties | ConvertTo-Json -Compress
                $logEntry += " | Properties: $propsJson"
            }
            
            # Output to appropriate stream based on level
            switch ($level) {
                ([LogLevel]::Debug) { Write-Debug $logEntry }
                ([LogLevel]::Info) { Write-Host $logEntry -ForegroundColor Green }
                ([LogLevel]::Warning) { Write-Warning $logEntry }
                ([LogLevel]::Error) { Write-Error $logEntry }
                ([LogLevel]::Critical) { Write-Error $logEntry }
            }
        }
    }
    
    [void] Debug([string]$message, [hashtable]$properties = @{}) {
        $this.WriteLog([LogLevel]::Debug, $message, $properties)
    }
    
    [void] Info([string]$message, [hashtable]$properties = @{}) {
        $this.WriteLog([LogLevel]::Info, $message, $properties)
    }
    
    [void] Warning([string]$message, [hashtable]$properties = @{}) {
        $this.WriteLog([LogLevel]::Warning, $message, $properties)
    }
    
    [void] Error([string]$message, [hashtable]$properties = @{}) {
        $this.WriteLog([LogLevel]::Error, $message, $properties)
    }
    
    [void] Critical([string]$message, [hashtable]$properties = @{}) {
        $this.WriteLog([LogLevel]::Critical, $message, $properties)
        throw $message
    }
}

# Global logger instance
$Global:Logger = [Logger]::new()

function Set-LogLevel {
    param([LogLevel]$Level)
    $Global:Logger.MinimumLevel = $Level
}

function Set-LogPrefix {
    param([string]$Prefix)
    $Global:Logger.LogPrefix = $Prefix
}

function Write-InfoLog {
    param(
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    $Global:Logger.Info($Message, $Properties)
}

function Write-WarningLog {
    param(
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    $Global:Logger.Warning($Message, $Properties)
}

function Write-ErrorLog {
    param(
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    $Global:Logger.Error($Message, $Properties)
}

function Write-CriticalLog {
    param(
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    $Global:Logger.Critical($Message, $Properties)
}

function Write-DebugLog {
    param(
        [string]$Message,
        [hashtable]$Properties = @{}
    )
    $Global:Logger.Debug($Message, $Properties)
}

# Export functions for module usage
Export-ModuleMember -Function @(
    'Set-LogLevel',
    'Set-LogPrefix', 
    'Write-InfoLog',
    'Write-WarningLog',
    'Write-ErrorLog',
    'Write-CriticalLog',
    'Write-DebugLog'
) -Variable @('Logger')
