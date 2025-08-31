#!/bin/bash
# wait-for-sqlserver.sh
# Waits for SQL Server to be ready for connections

set -e

TIMEOUT=${1:-60}
HOST=${2:-localhost}
PORT=${3:-1433}
SA_PASSWORD=${4:-$SA_PASSWORD}

echo "Waiting for SQL Server to be ready on $HOST:$PORT (timeout: ${TIMEOUT}s)..."

for i in $(seq 1 $TIMEOUT); do
    if /opt/mssql-tools/bin/sqlcmd -S "$HOST,$PORT" -U sa -P "$SA_PASSWORD" -Q "SELECT 1" &>/dev/null; then
        echo "SQL Server is ready!"
        exit 0
    fi
    
    echo "Waiting for SQL Server... ($i/$TIMEOUT)"
    sleep 1
done

echo "Timeout waiting for SQL Server to be ready"
exit 1
