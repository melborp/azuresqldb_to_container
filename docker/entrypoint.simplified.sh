#!/bin/bash
# entrypoint.sh - Simplified entrypoint with BACPAC import and script execution

set -e

# Configuration
DATABASE_NAME=${DATABASE_NAME:-ImportedDatabase}
SA_PASSWORD=${SA_PASSWORD:-YourStrong@Passw0rd123}
BACPAC_FILE="/var/opt/mssql/backup/database.bacpac"
MIGRATION_SCRIPTS_DIR="/var/opt/mssql/scripts/migrations"
UPGRADE_SCRIPTS_DIR="/var/opt/mssql/scripts/upgrades"
LOG_FILE="/var/opt/mssql/logs/initialization.log"

# Initialize logging
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

handle_error() {
    log "ERROR: $1"
    exit 1
}

# Check if database already exists (for container restarts)
database_exists() {
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SELECT name FROM sys.databases WHERE name = '$DATABASE_NAME'" -h -1 | grep -q "$DATABASE_NAME" 2>/dev/null
}

# Import BACPAC if database doesn't exist
import_bacpac_if_needed() {
    if database_exists; then
        log "Database '$DATABASE_NAME' already exists, skipping import"
        return 0
    fi

    if [ ! -f "$BACPAC_FILE" ]; then
        handle_error "BACPAC file not found: $BACPAC_FILE"
    fi

    log "Importing BACPAC: $DATABASE_NAME"
    local connection_string="Server=localhost;Database=master;User Id=sa;Password=$SA_PASSWORD;TrustServerCertificate=true;"
    
    if /opt/sqlpackage/sqlpackage /Action:Import \
        /SourceFile:"$BACPAC_FILE" \
        /TargetConnectionString:"$connection_string" \
        /TargetDatabaseName:"$DATABASE_NAME" \
        /DiagnosticsFile:"/var/opt/mssql/logs/sqlpackage.log" \
        /OverwriteFiles:true; then
        log "BACPAC import completed successfully"
        
        # Remove BACPAC file after successful import to save space
        rm -f "$BACPAC_FILE"
        log "BACPAC file removed to save space"
    else
        handle_error "BACPAC import failed"
    fi
}

# Execute SQL scripts in directory
execute_scripts() {
    local scripts_dir="$1"
    local script_type="$2"
    
    if [ ! -d "$scripts_dir" ] || [ -z "$(ls -A "$scripts_dir" 2>/dev/null)" ]; then
        log "No $script_type scripts found"
        return 0
    fi
    
    log "Executing $script_type scripts from: $scripts_dir"
    find "$scripts_dir" -name "*.sql" | sort | while read -r script_file; do
        log "Executing: $(basename "$script_file")"
        if /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -d "$DATABASE_NAME" -i "$script_file" -b; then
            log "Successfully executed: $(basename "$script_file")"
        else
            handle_error "Failed to execute: $(basename "$script_file")"
        fi
    done
}

# Main initialization function
initialize_database() {
    log "=== Database Initialization Started ==="
    
    # Wait for SQL Server to be ready
    log "Waiting for SQL Server to be ready..."
    /opt/mssql-tools/bin/wait-for-sqlserver.sh 60 localhost 1433 "$SA_PASSWORD" || handle_error "SQL Server failed to start"
    
    # Import BACPAC if needed
    import_bacpac_if_needed
    
    # Execute migration scripts
    execute_scripts "$MIGRATION_SCRIPTS_DIR" "migration"
    
    # Execute upgrade scripts  
    execute_scripts "$UPGRADE_SCRIPTS_DIR" "upgrade"
    
    log "=== Database Initialization Completed ==="
}

# Start SQL Server in background
log "Starting SQL Server..."
/opt/mssql/bin/sqlservr &
SQLSERVER_PID=$!

# Wait for SQL Server and initialize database
sleep 10
initialize_database

# Keep SQL Server running
log "SQL Server ready with database: $DATABASE_NAME"
wait $SQLSERVER_PID
