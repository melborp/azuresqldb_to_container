#!/bin/bash
# entrypoint.sh
# Main entrypoint script for SQL Server container with BACPAC import and script execution

set -e

# Default values
DATABASE_NAME=${DATABASE_NAME:-ImportedDatabase}
SA_PASSWORD=${SA_PASSWORD:-YourStrong@Passw0rd123}
BACPAC_FILE=${BACPAC_FILE:-/var/opt/mssql/backup/database.bacpac}
MIGRATION_SCRIPTS_DIR="/var/opt/mssql/scripts/migrations"
UPGRADE_SCRIPTS_DIR="/var/opt/mssql/scripts/upgrades"
LOG_DIR="/var/opt/mssql/logs"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/container-setup.log"
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
    log "Starting BACPAC import: $DATABASE_NAME"
    
    local connection_string="Server=localhost;Database=master;User Id=sa;Password=$SA_PASSWORD;TrustServerCertificate=true;"
    
    # Import BACPAC using sqlpackage
    if /opt/sqlpackage/sqlpackage /Action:Import \
        /SourceFile:"$BACPAC_FILE" \
        /TargetConnectionString:"$connection_string" \
        /TargetDatabaseName:"$DATABASE_NAME" \
        /DiagnosticsFile:"$LOG_DIR/sqlpackage-diagnostics.log" \
        /OverwriteFiles:true &>> "$LOG_DIR/bacpac-import.log"; then
        
        log "BACPAC import completed successfully"
        
        # Verify database was created
        if /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SELECT name FROM sys.databases WHERE name = '$DATABASE_NAME'" -h -1 | grep -q "$DATABASE_NAME"; then
            log "Database verification successful: $DATABASE_NAME"
        else
            handle_error "Database verification failed: $DATABASE_NAME not found"
        fi
    else
        handle_error "BACPAC import failed"
    fi
}

# Database setup function
setup_database() {
    log "Starting database setup process"
    
    # Verify BACPAC file
    verify_bacpac
    
    # Wait for SQL Server to be ready
    log "Waiting for SQL Server to be ready..."
    /opt/mssql-tools/bin/wait-for-sqlserver.sh 60 localhost 1433 "$SA_PASSWORD" || handle_error "SQL Server failed to start"
    
    # Import BACPAC
    import_bacpac
    
    # Execute migration scripts
    log "Executing migration scripts..."
    execute_scripts_in_directory "$MIGRATION_SCRIPTS_DIR" "migration"
    
    # Execute upgrade scripts
    log "Executing upgrade scripts..."
    execute_scripts_in_directory "$UPGRADE_SCRIPTS_DIR" "upgrade"
    
    log "Database setup completed successfully"
}

# Main execution
main() {
    log "=== SQL Server Container Startup ==="
    log "Database Name: $DATABASE_NAME"
    log "BACPAC File: $BACPAC_FILE"
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Start SQL Server in background
    log "Starting SQL Server..."
    /opt/mssql/bin/sqlservr &
    SQLSERVER_PID=$!
    
    # Wait a moment for SQL Server to initialize
    sleep 10
    
    # Setup database (this will exit container if any step fails)
    setup_database
    
    # If we get here, everything succeeded
    log "=== Container setup completed successfully ==="
    log "SQL Server is ready with database: $DATABASE_NAME"
    
    # Keep SQL Server running in foreground
    wait $SQLSERVER_PID
}

# Handle signals
trap 'log "Received shutdown signal"; kill $SQLSERVER_PID 2>/dev/null; exit 0' SIGTERM SIGINT

# Execute main function
main
