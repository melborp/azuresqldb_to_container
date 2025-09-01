#!/bin/bash
# import-bacpac.sh
# Imports BACPAC file during Docker build stage

set -e

# Default values
DATABASE_NAME=${DATABASE_NAME:-ImportedDatabase}
SA_PASSWORD=${SA_PASSWORD:-YourStrong@Passw0rd123}
BACPAC_FILE=${BACPAC_FILE:-/var/opt/mssql/backup/database.bacpac}
LOG_DIR="/var/opt/mssql/logs"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] IMPORT: $1" | tee -a "$LOG_DIR/build-import.log"
}

# Error handling function
handle_error() {
    log "ERROR: $1"
    exit 1
}

# Verify BACPAC file function
verify_bacpac() {
    if [ ! -f "$BACPAC_FILE" ]; then
        handle_error "BACPAC file not found: $BACPAC_FILE"
    fi
    
    local file_size=$(stat -c%s "$BACPAC_FILE")
    local file_size_mb=$((file_size / 1024 / 1024))
    
    log "BACPAC file found: $BACPAC_FILE (${file_size_mb} MB)"
    
    if [ "$file_size" -lt 1024 ]; then
        handle_error "BACPAC file appears to be too small: ${file_size} bytes"
    fi
}

# Import BACPAC function
import_bacpac() {
    log "Starting BACPAC import during build: $DATABASE_NAME"
    
    # Import BACPAC using sqlpackage with separate connection parameters
    log "Executing sqlpackage import command..."
    if /opt/sqlpackage/sqlpackage /Action:Import \
        /SourceFile:"$BACPAC_FILE" \
        /TargetServerName:"localhost" \
        /TargetDatabaseName:"$DATABASE_NAME" \
        /TargetUser:"sa" \
        /TargetPassword:"$SA_PASSWORD" \
        /TargetTrustServerCertificate:true \
        /DiagnosticsFile:"$LOG_DIR/sqlpackage-diagnostics.log" &>> "$LOG_DIR/bacpac-import.log"; then
        
        log "BACPAC import completed successfully during build"
        
        # Verify database was created
        if /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SELECT name FROM sys.databases WHERE name = '$DATABASE_NAME'" -h -1 | grep -q "$DATABASE_NAME"; then
            log "Database verification successful during build: $DATABASE_NAME"
        else
            handle_error "Database verification failed during build: $DATABASE_NAME not found"
        fi
    else
        log "sqlpackage import failed. Checking logs..."
        if [ -f "$LOG_DIR/bacpac-import.log" ]; then
            log "Import log contents:"
            tail -10 "$LOG_DIR/bacpac-import.log" | while read line; do
                log "  $line"
            done
        fi
        if [ -f "$LOG_DIR/sqlpackage-diagnostics.log" ]; then
            log "Diagnostics log contents:"
            tail -10 "$LOG_DIR/sqlpackage-diagnostics.log" | while read line; do
                log "  $line"
            done
        fi
        handle_error "BACPAC import failed during build"
    fi
}

# Main execution
main() {
    log "=== BACPAC Import During Build Started ==="
    log "Database Name: $DATABASE_NAME"
    log "BACPAC File: $BACPAC_FILE"
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Start SQL Server in background
    log "Starting SQL Server for build import..."
    
    # Set SQL Server environment variables
    export ACCEPT_EULA=Y
    export MSSQL_SA_PASSWORD="$SA_PASSWORD"
    export MSSQL_PID=Express
    
    # Ensure SQL Server directories exist and have proper permissions
    mkdir -p /var/opt/mssql/data
    mkdir -p /var/opt/mssql/log
    mkdir -p /var/opt/mssql/backup
    chown -R mssql:root /var/opt/mssql/
    
    # Start SQL Server as mssql user with proper error handling
    runuser -u mssql /opt/mssql/bin/sqlservr > /var/opt/mssql/log/sqlservr-build.log 2>&1 &
    SQLSERVER_PID=$!
    
    # Give SQL Server a moment to start
    sleep 5
    
    # Check if SQL Server process is still running
    if ! kill -0 $SQLSERVER_PID 2>/dev/null; then
        log "SQL Server failed to start. Check logs:"
        tail -20 /var/opt/mssql/log/sqlservr-build.log 2>/dev/null || log "Could not read SQL Server startup log"
        handle_error "SQL Server process failed to start"
    fi
    
    log "SQL Server process started with PID: $SQLSERVER_PID"
    
    # Wait for SQL Server to be ready
    log "Waiting for SQL Server to be ready during build..."
    local timeout=120  # Increased timeout to 2 minutes
    for i in $(seq 1 $timeout); do
        # Try multiple connection methods
        if /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SELECT 1" -t 10 &>/dev/null; then
            log "SQL Server is ready for import!"
            break
        elif /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SELECT 1" -C -t 10 &>/dev/null; then
            log "SQL Server is ready for import (using sqlcmd18)!"
            break
        fi
        
        if [ $i -eq $timeout ]; then
            log "Final connection attempt failed. SQL Server logs:"
            tail -20 /var/opt/mssql/log/errorlog 2>/dev/null || log "Could not read SQL Server errorlog"
            handle_error "Timeout waiting for SQL Server during build after $timeout seconds"
        fi
        
        # Show progress every 10 seconds
        if [ $((i % 10)) -eq 0 ]; then
            log "Still waiting for SQL Server... ($i/$timeout) - checking SQL Server process"
            if ps aux | grep -q "[s]qlservr"; then
                log "SQL Server process is running"
            else
                log "SQL Server process not found!"
            fi
        else
            log "Waiting for SQL Server... ($i/$timeout)"
        fi
        sleep 1
    done
    
    # Verify BACPAC file
    verify_bacpac
    
    # Import BACPAC
    import_bacpac
    
    # Gracefully shutdown SQL Server
    log "Shutting down SQL Server after import..."
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SHUTDOWN WITH NOWAIT" || true
    sleep 5
    kill $SQLSERVER_PID 2>/dev/null || true
    wait $SQLSERVER_PID 2>/dev/null || true
    
    log "=== BACPAC Import During Build Completed Successfully ==="
}

# Execute main function
main
