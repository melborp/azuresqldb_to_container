# Multi-stage Dockerfile for SQL Server with BACPAC import during build
# Stage 1: Import BACPAC and create database
FROM mcr.microsoft.com/mssql/server:2022-latest AS builder

# Accept build arguments
ARG SA_PASSWORD
ARG DATABASE_NAME=ImportedDatabase
ARG BACPAC_FILE=database.bacpac
ARG ACCEPT_EULA=Y

# Set environment variables
ENV ACCEPT_EULA=$ACCEPT_EULA
ENV SA_PASSWORD=$SA_PASSWORD
ENV DATABASE_NAME=$DATABASE_NAME
ENV BACPAC_FILE=/var/opt/mssql/backup/database.bacpac
ENV MSSQL_PID=Express

# Add mssql-tools18 to PATH (already included in base image)
ENV PATH="$PATH:/opt/mssql-tools18/bin"

# Install necessary tools for BACPAC import
USER root
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install sqlpackage for BACPAC import (mssql-tools18 already included in base image)
RUN curl -L https://aka.ms/sqlpackage-linux -o sqlpackage.zip \
    && unzip sqlpackage.zip -d /opt/sqlpackage \
    && chmod +x /opt/sqlpackage/sqlpackage \
    && rm sqlpackage.zip

# Create directories
RUN mkdir -p /var/opt/mssql/backup \
    && mkdir -p /var/opt/mssql/logs

# Copy BACPAC file (only needed during build)
COPY database.bacpac /var/opt/mssql/backup/database.bacpac

# Copy import script
COPY import-bacpac.sh /opt/mssql-tools/bin/
RUN chmod +x /opt/mssql-tools/bin/import-bacpac.sh

# Set permissions
RUN chown -R mssql:root /var/opt/mssql/ \
    && chown -R mssql:root /opt/mssql-tools/

# Import BACPAC as root (SQL Server needs root privileges in Docker)
USER root

# Start SQL Server and import BACPAC
RUN /opt/mssql-tools/bin/import-bacpac.sh

# Stage 2: Final runtime image (without BACPAC file)
FROM mcr.microsoft.com/mssql/server:2022-latest AS final

# Accept build arguments
ARG SA_PASSWORD
ARG DATABASE_NAME=ImportedDatabase
ARG ACCEPT_EULA=Y

# Set environment variables
ENV ACCEPT_EULA=$ACCEPT_EULA
ENV SA_PASSWORD=$SA_PASSWORD
ENV DATABASE_NAME=$DATABASE_NAME
ENV MSSQL_PID=Express

# Add mssql-tools18 to PATH (already included in base image)
ENV PATH="$PATH:/opt/mssql-tools18/bin"

# Install runtime dependencies (minimal - mssql-tools18 already included in base image)
USER root
RUN apt-get update \
    && rm -rf /var/lib/apt/lists/*

# Create directories for scripts and logs
RUN mkdir -p /opt/migration-scripts \
    && mkdir -p /var/opt/mssql/logs

# Copy runtime scripts
COPY entrypoint.sh /opt/mssql-tools/bin/

# Make scripts executable
RUN chmod +x /opt/mssql-tools/bin/*.sh

# Copy SQL migration scripts (this directory may be empty)
COPY sql-scripts/migrations/ /opt/migration-scripts/

# Copy database files from builder stage (if they exist)
COPY --from=builder /var/opt/mssql/data/ /var/opt/mssql/data/

# Set permissions
RUN chown -R mssql:root /var/opt/mssql/ \
    && chown -R mssql:root /opt/mssql-tools/ \
    && chown -R mssql:root /opt/migration-scripts/

# Health check
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
    CMD /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "SELECT 1" || exit 1

# Switch back to mssql user
USER mssql

# Expose SQL Server port
EXPOSE 1433

# Set entrypoint
ENTRYPOINT ["/opt/mssql-tools/bin/entrypoint.sh"]
