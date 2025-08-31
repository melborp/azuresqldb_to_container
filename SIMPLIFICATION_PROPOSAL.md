# SIMPLIFIED SOLUTION RECOMMENDATION

## Architecture Change
**From**: Multi-stage Docker build with complex file copying
**To**: Single-stage build with smart initialization and cleanup

## Key Simplifications

### 1. Single Dockerfile
- One stage with BACPAC import during first container startup
- BACPAC file removed after import to save space
- Simpler, more reliable approach

### 2. Consolidated Scripts
- Merge import-bacpac.sh into entrypoint.sh
- Reduce helper function complexity
- Remove redundant validation

### 3. Simplified Parameters
- Reduce orchestrator script parameters by 30%
- Group related settings
- Remove rarely-used options

### 4. Improved Reliability
- Database import happens at runtime (more reliable)
- Container restart-safe (checks if DB already exists)
- Automatic cleanup of BACPAC after import

## Benefits
✅ More reliable database import
✅ Simpler Docker build process
✅ Container restart-safe
✅ Still achieves space savings (BACPAC removed after import)
✅ Easier to debug and maintain
✅ Better error handling

## Trade-offs
⚠️ Database import happens at first startup (slightly longer first start)
⚠️ BACPAC briefly present in running container (but removed after import)

## Recommendation
**ADOPT** the simplified single-stage approach for better reliability and maintainability.
