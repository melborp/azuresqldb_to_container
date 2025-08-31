#!/bin/bash
# entrypoint.sh
# Main entrypoint script for SQL Server container with migration/upgrade script execution
# BACPAC import is handled during build stage

set -e

# Default values
DATABASE_NAME=${DATABASE_NAME:-ImportedDatabase}
SA_PASSWORD=${SA_PASSWORD:-YourStrong@Passw0rd123}
MIGRATION_SCRIPTS_DIR="/var/opt/mssql/scripts/migrations"
UPGRADE_SCRIPTS_DIR="/var/opt/mssql/scripts/upgrades"
LOG_DIR="/var/opt/mssql/logs"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RUNTIME: $1" | tee -a "$LOG_DIR/container-runtime.log"
}

# Error handling function
handle_error() {
    log "ERROR: $1"
    exit 1
}

# Execute SQL script function
execute_sql_script() {
    local script_file="$1"
    local script_type="$2"
    
    log "Executing $script_type script: $(basename "$script_file")"
    
    # Execute script and capture output
    if /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -d "$DATABASE_NAME" -i "$script_file" -b -V 1 &>> "$LOG_DIR/script-execution.log"; then
        log "Successfully executed $script_type script: $(basename "$script_file")"
        return 0
    else
        handle_error "Failed to execute $script_type script: $(basename "$script_file")"
    fi
}

# Execute scripts in directory function
execute_scripts_in_directory() {
    local scripts_dir="$1"
    local script_type="$2"
    
    if [ ! -d "$scripts_dir" ]; then
        log "No $script_type scripts directory found: $scripts_dir"
        return 0
    fi
    
    # Count SQL files
    script_count=$(find "$scripts_dir" -name "*.sql" | wc -l)
    
    if [ "$script_count" -eq 0 ]; then
        log "No $script_type scripts found in: $scripts_dir"
        return 0
    fi
    
    log "Found $script_count $script_type script(s) to execute"
    
    # Execute scripts in alphabetical order
    find "$scripts_dir" -name "*.sql" | sort | while read -r script_file; do
        execute_sql_script "$script_file" "$script_type"
    done
}

# Verify database exists (imported during build)
verify_database() {
    log "Verifying imported database exists: $DATABASE_NAME"
    
    if /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SELECT name FROM sys.databases WHERE name = '$DATABASE_NAME'" -h -1 | grep -q "$DATABASE_NAME"; then
        log "Database verification successful: $DATABASE_NAME"
        
        # Get database info
        local db_size=$(/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -d "$DATABASE_NAME" -Q "SELECT CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(10,2)) FROM sys.master_files WHERE database_id = DB_ID('$DATABASE_NAME')" -h -1 | tr -d ' ')
        log "Database size: ${db_size} MB"
    else
        handle_error "Database not found: $DATABASE_NAME. BACPAC import may have failed during build."
    fi
}

# Database setup function (migration/upgrade scripts only)
setup_database() {
    log "Starting database runtime setup process"
    
    # Wait for SQL Server to be ready
    log "Waiting for SQL Server to be ready..."
    /opt/mssql-tools/bin/wait-for-sqlserver.sh 60 localhost 1433 "$SA_PASSWORD" || handle_error "SQL Server failed to start"
    
    # Verify imported database exists
    verify_database
    
    # Execute migration scripts
    log "Executing migration scripts..."
    execute_scripts_in_directory "$MIGRATION_SCRIPTS_DIR" "migration"
    
    # Execute upgrade scripts
    log "Executing upgrade scripts..."
    execute_scripts_in_directory "$UPGRADE_SCRIPTS_DIR" "upgrade"
    
    log "Database runtime setup completed successfully"
}

# Main execution
main() {
    log "=== SQL Server Container Runtime Startup ==="
    log "Database Name: $DATABASE_NAME"
    log "Migration Scripts Dir: $MIGRATION_SCRIPTS_DIR"
    log "Upgrade Scripts Dir: $UPGRADE_SCRIPTS_DIR"
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Start SQL Server in background
    log "Starting SQL Server..."
    /opt/mssql/bin/sqlservr &
    SQLSERVER_PID=$!
    
    # Wait a moment for SQL Server to initialize
    sleep 10
    
    # Setup database (migration/upgrade scripts only)
    setup_database
    
    # If we get here, everything succeeded
    log "=== Container runtime setup completed successfully ==="
    log "SQL Server is ready with database: $DATABASE_NAME"
    
    # Keep SQL Server running in foreground
    wait $SQLSERVER_PID
}

# Handle signals
trap 'log "Received shutdown signal"; kill $SQLSERVER_PID 2>/dev/null; exit 0' SIGTERM SIGINT

# Execute main function
main
