#!/bin/bash
# entrypoint.sh - Simplified SQL Server entrypoint
# 1. Start SQL Server
# 2. Run migration scripts 
# 3. Keep SQL Server running in foreground

set -e

# Default values
DATABASE_NAME=${DATABASE_NAME:-ImportedDatabase}
SA_PASSWORD=${SA_PASSWORD:-YourStrong@Passw0rd123}
MIGRATION_SCRIPTS_DIR="/opt/migration-scripts"

echo "[$(date)] Starting SQL Server for migration setup..."

# 1. Start SQL Server in background for migration setup
/opt/mssql/bin/sqlservr &
SQLSERVER_PID=$!

# Wait for SQL Server to be ready
echo "[$(date)] Waiting for SQL Server..."
for i in {1..60}; do
    if /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT 1" &>/dev/null; then
        echo "[$(date)] SQL Server is ready!"
        break
    fi
    echo "Waiting... ($i/60)"
    sleep 1
done

# 2. Run migration scripts
if [ -d "$MIGRATION_SCRIPTS_DIR" ]; then
    echo "[$(date)] Executing migration scripts..."
    for script in "$MIGRATION_SCRIPTS_DIR"/*.sql; do
        if [ -f "$script" ]; then
            echo "[$(date)] Running: $(basename "$script")"
            /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -d "$DATABASE_NAME" -i "$script"
        fi
    done
    echo "[$(date)] Migration scripts completed"
else
    echo "[$(date)] No migration scripts directory found"
fi

# 3. Stop background SQL Server and start in foreground
echo "[$(date)] Restarting SQL Server in foreground for container runtime..."
kill $SQLSERVER_PID
wait $SQLSERVER_PID

# Start SQL Server as PID 1 (foreground)
echo "[$(date)] Starting SQL Server as main process..."
exec /opt/mssql/bin/sqlservr
