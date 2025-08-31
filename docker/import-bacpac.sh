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
    
    local connection_string="Server=localhost;Database=master;User Id=sa;Password=$SA_PASSWORD;TrustServerCertificate=true;"
    
    # Import BACPAC using sqlpackage
    if /opt/sqlpackage/sqlpackage /Action:Import \
        /SourceFile:"$BACPAC_FILE" \
        /TargetConnectionString:"$connection_string" \
        /TargetDatabaseName:"$DATABASE_NAME" \
        /DiagnosticsFile:"$LOG_DIR/sqlpackage-diagnostics.log" \
        /OverwriteFiles:true &>> "$LOG_DIR/bacpac-import.log"; then
        
        log "BACPAC import completed successfully during build"
        
        # Verify database was created
        if /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SELECT name FROM sys.databases WHERE name = '$DATABASE_NAME'" -h -1 | grep -q "$DATABASE_NAME"; then
            log "Database verification successful during build: $DATABASE_NAME"
        else
            handle_error "Database verification failed during build: $DATABASE_NAME not found"
        fi
    else
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
    /opt/mssql/bin/sqlservr &
    SQLSERVER_PID=$!
    
    # Wait for SQL Server to be ready
    log "Waiting for SQL Server to be ready during build..."
    local timeout=60
    for i in $(seq 1 $timeout); do
        if /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SELECT 1" &>/dev/null; then
            log "SQL Server is ready for import!"
            break
        fi
        
        if [ $i -eq $timeout ]; then
            handle_error "Timeout waiting for SQL Server during build"
        fi
        
        log "Waiting for SQL Server... ($i/$timeout)"
        sleep 1
    done
    
    # Verify BACPAC file
    verify_bacpac
    
    # Import BACPAC
    import_bacpac
    
    # Gracefully shutdown SQL Server
    log "Shutting down SQL Server after import..."
    kill $SQLSERVER_PID
    wait $SQLSERVER_PID 2>/dev/null || true
    
    log "=== BACPAC Import During Build Completed Successfully ==="
}

# Execute main function
main
