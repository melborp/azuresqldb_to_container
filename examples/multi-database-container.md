# Multi-Database Container Example

This example demonstrates how to create a SQL Server container with multiple databases using the new modular scripts.

## Scenario
- Application Database (from BACPAC)
- Configuration Database (from BACPAC)  
- Runtime migration scripts for schema updates

## Step 1: Download BACPAC Files

```powershell
# Download application database BACPAC
.\scripts\Download-FileFromBlobStorage.ps1 `
    -BlobUrl "https://mystorageaccount.blob.core.windows.net/bacpacs/application.bacpac" `
    -LocalPath ".\temp\application.bacpac" `
    -Force `
    -VerifyIntegrity

# Download configuration database BACPAC
.\scripts\Download-FileFromBlobStorage.ps1 `
    -BlobUrl "https://mystorageaccount.blob.core.windows.net/bacpacs/configuration.bacpac" `
    -LocalPath ".\temp\configuration.bacpac" `
    -Force `
    -VerifyIntegrity
```

## Step 2: Prepare Migration Scripts

Create migration scripts directory structure:
```
migrations/
├── 001_create_app_indexes.sql
├── 002_update_config_schema.sql
└── 003_seed_reference_data.sql
```

Example migration script (`migrations/001_create_app_indexes.sql`):
```sql
-- Create performance indexes on application database
USE ApplicationDB;

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Users_Email')
BEGIN
    CREATE INDEX IX_Users_Email ON Users(Email);
    PRINT 'Created index IX_Users_Email on ApplicationDB';
END

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Orders_CustomerID')
BEGIN
    CREATE INDEX IX_Orders_CustomerID ON Orders(CustomerID);
    PRINT 'Created index IX_Orders_CustomerID on ApplicationDB';
END
```

## Step 3: Build Multi-Database Docker Image

```powershell
# Create secure password
$securePassword = ConvertTo-SecureString "MySecurePassword123!" -AsPlainText -Force

# Build image with multiple databases
.\scripts\Build-SqlServerImage.ps1 `
    -ImageName "my-multi-db-app" `
    -ImageTag "v1.0.0" `
    -BacpacPaths @(".\temp\application.bacpac", ".\temp\configuration.bacpac") `
    -DatabaseNames @("ApplicationDB", "ConfigurationDB") `
    -MigrationScriptPaths @(".\migrations\*.sql") `
    -SqlServerPassword $securePassword `
    -LogLevel "Info"
```

## Step 4: Run the Container

### Basic Run (without migration scripts)
```bash
docker run -d -p 1433:1433 \
  --name my-sql-app \
  -e SA_PASSWORD='MySecurePassword123!' \
  my-multi-db-app:v1.0.0
```

### Run with Runtime Migration Scripts
```bash
# Create runtime migrations directory
mkdir -p ./runtime-migrations

# Add runtime-specific migration scripts
cat > ./runtime-migrations/004_runtime_config.sql << 'EOF'
-- Runtime configuration updates
USE ConfigurationDB;

UPDATE Settings 
SET Value = 'Production' 
WHERE SettingKey = 'Environment';

PRINT 'Updated runtime configuration';
EOF

# Run container with mounted migration scripts
docker run -d -p 1433:1433 \
  --name my-sql-app \
  -e SA_PASSWORD='MySecurePassword123!' \
  -v $(pwd)/runtime-migrations:/var/opt/mssql/migration-scripts:ro \
  my-multi-db-app:v1.0.0
```

## Step 5: Verify Deployment

```bash
# Check container status
docker logs my-sql-app

# Connect to SQL Server
docker exec -it my-sql-app /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P 'MySecurePassword123!' \
  -Q "SELECT name FROM sys.databases WHERE name IN ('ApplicationDB', 'ConfigurationDB')"
```

## Expected Output

### Build Output
```
##[section]Build Results
CONTAINER_IMAGE=my-multi-db-app:v1.0.0
IMAGE_NAME=my-multi-db-app
IMAGE_TAG=v1.0.0
DATABASE_COUNT=2
DATABASES=ApplicationDB,ConfigurationDB
MIGRATION_SCRIPTS_COUNT=3
MIGRATION_MOUNT_PATH=/var/opt/mssql/migration-scripts
FINAL_IMAGE_SIZE_MB=2048.5
BACPAC_IN_FINAL_IMAGE=FALSE

##[section]Usage Instructions
To run with migration scripts:
docker run -d -p 1433:1433 -e SA_PASSWORD='[YourPassword]' -v /path/to/migration-scripts:/var/opt/mssql/migration-scripts my-multi-db-app:v1.0.0
```

### Container Startup Logs
```
Starting SQL Server with imported databases...
Waiting for SQL Server to start...
Found migration scripts in /var/opt/mssql/migration-scripts
Executing migration script: 001_create_app_indexes.sql
Created index IX_Users_Email on ApplicationDB
Created index IX_Orders_CustomerID on ApplicationDB
Executing migration script: 002_update_config_schema.sql
...
Executing migration script: 004_runtime_config.sql
Updated runtime configuration
Migration scripts execution completed
SQL Server is ready for connections
```

## Key Benefits

1. **Multiple Databases**: Application and configuration data separated
2. **Build-Time Import**: BACPAC files imported during build, not included in final image
3. **Runtime Flexibility**: Migration scripts mounted as volumes for easy updates
4. **Optimized Size**: Final image contains only SQL Server + imported databases
5. **CI/CD Ready**: Parameterized scripts for automated pipelines

## Advanced Usage

### Docker Compose Example
```yaml
version: '3.8'
services:
  database:
    image: my-multi-db-app:v1.0.0
    ports:
      - "1433:1433"
    environment:
      - SA_PASSWORD=MySecurePassword123!
    volumes:
      - ./runtime-migrations:/var/opt/mssql/migration-scripts:ro
      - sqlserver-data:/var/opt/mssql/data
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P $$SA_PASSWORD -Q 'SELECT 1'"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  sqlserver-data:
```

### Kubernetes Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-db-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: multi-db-app
  template:
    metadata:
      labels:
        app: multi-db-app
    spec:
      containers:
      - name: sqlserver
        image: my-multi-db-app:v1.0.0
        ports:
        - containerPort: 1433
        env:
        - name: SA_PASSWORD
          valueFrom:
            secretKeyRef:
              name: sql-secret
              key: sa-password
        volumeMounts:
        - name: migration-scripts
          mountPath: /var/opt/mssql/migration-scripts
          readOnly: true
      volumes:
      - name: migration-scripts
        configMap:
          name: migration-scripts-config
```
