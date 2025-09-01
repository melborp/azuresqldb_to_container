#!/bin/bash
# Debug version of import-bacpac.sh for testing SQL Server startup

set -e  # Exit on any error

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >&2
}

# Error handling function
handle_error() {
    local error_message="$1"
    log "ERROR: $error_message"
    
    # Show process status
    log "Current processes:"
    ps aux | grep -E "(sqlservr|mssql)" || log "No SQL Server processes found"
    
    # Show SQL Server logs if available
    if [ -f "/var/opt/mssql/log/sqlservr-build.log" ]; then
        log "SQL Server startup log (last 20 lines):"
        tail -20 /var/opt/mssql/log/sqlservr-build.log
    fi
    
    # Show error log if available
    if [ -f "/var/opt/mssql/log/errorlog" ]; then
        log "SQL Server error log (last 10 lines):"
        tail -10 /var/opt/mssql/log/errorlog
    fi
    
    exit 1
}

# Test if we're in the right environment
log "=== Environment Check ==="
log "User: $(whoami)"
log "SA_PASSWORD set: $([ -n "$SA_PASSWORD" ] && echo "Yes" || echo "No")"
log "BACPAC_FILE: ${BACPAC_FILE:-not set}"
log "DATABASE_NAME: ${DATABASE_NAME:-not set}"

# Check if SQL Server binaries exist
log "=== Binary Check ==="
if [ -f "/opt/mssql/bin/sqlservr" ]; then
    log "sqlservr binary found"
    ls -la /opt/mssql/bin/sqlservr
else
    handle_error "sqlservr binary not found"
fi

if [ -f "/opt/mssql-tools/bin/sqlcmd" ]; then
    log "sqlcmd binary found"
    ls -la /opt/mssql-tools/bin/sqlcmd
else
    log "Legacy sqlcmd not found, checking for newer version"
fi

if [ -f "/opt/mssql-tools18/bin/sqlcmd" ]; then
    log "sqlcmd18 binary found"
    ls -la /opt/mssql-tools18/bin/sqlcmd
else
    log "sqlcmd18 not found"
fi

# Set up directories
log "=== Directory Setup ==="
mkdir -p /var/opt/mssql/data
mkdir -p /var/opt/mssql/log
mkdir -p /var/opt/mssql/backup
chown -R mssql:root /var/opt/mssql/

log "Directory permissions:"
ls -la /var/opt/mssql/

# Set SQL Server environment variables
log "=== Environment Setup ==="
export ACCEPT_EULA=Y
export MSSQL_SA_PASSWORD="$SA_PASSWORD"
export MSSQL_PID=Express

log "Environment variables set"

# Start SQL Server
log "=== Starting SQL Server ==="
log "Starting SQL Server as mssql user..."

# Try to start SQL Server and capture any immediate errors
sudo -u mssql /opt/mssql/bin/sqlservr > /var/opt/mssql/log/sqlservr-build.log 2>&1 &
SQLSERVER_PID=$!

log "SQL Server started with PID: $SQLSERVER_PID"

# Give SQL Server time to initialize
log "Waiting for SQL Server to initialize..."
sleep 10

# Check if the process is still running
if ! kill -0 $SQLSERVER_PID 2>/dev/null; then
    handle_error "SQL Server process died during startup"
fi

log "SQL Server process is still running"

# Test connectivity with multiple methods
log "=== Testing Connectivity ==="

# Try different sqlcmd locations and connection methods
SQLCMD_PATHS=(
    "/opt/mssql-tools/bin/sqlcmd"
    "/opt/mssql-tools18/bin/sqlcmd"
)

CONNECTION_METHODS=(
    "-S localhost -U sa -P $SA_PASSWORD"
    "-S localhost,1433 -U sa -P $SA_PASSWORD"
    "-S 127.0.0.1 -U sa -P $SA_PASSWORD"
    "-S 127.0.0.1,1433 -U sa -P $SA_PASSWORD"
)

SQLCMD_FOUND=false
for SQLCMD_PATH in "${SQLCMD_PATHS[@]}"; do
    if [ -f "$SQLCMD_PATH" ]; then
        log "Testing with $SQLCMD_PATH"
        SQLCMD_FOUND=true
        
        for method in "${CONNECTION_METHODS[@]}"; do
            log "Trying: $SQLCMD_PATH $method"
            
            # Try with different timeouts
            for timeout in 30 60 90; do
                log "Attempt with ${timeout}s timeout..."
                if timeout $timeout $SQLCMD_PATH $method -Q "SELECT @@VERSION" 2>&1; then
                    log "SUCCESS: Connected to SQL Server!"
                    log "=== SQL Server is ready ==="
                    exit 0
                else
                    log "Failed with ${timeout}s timeout"
                fi
                sleep 5
            done
        done
    fi
done

if [ "$SQLCMD_FOUND" = false ]; then
    handle_error "No sqlcmd binary found in expected locations"
fi

handle_error "All connection attempts failed after extended timeouts"
