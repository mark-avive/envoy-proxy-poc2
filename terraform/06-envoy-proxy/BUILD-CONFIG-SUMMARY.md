# Build Script Configuration Summary

## Overview
The `build-custom-envoy.sh` script has been fully refactored to use configuration files instead of hardcoded values or command-line arguments.

## Configuration Files

### `build-config.env`
Contains all variables used by the build script:
- AWS settings (region, profile)
- ECR repository configuration
- Docker build options
- Image tagging options
- Cleanup preferences

### `build-config.env.example`
Template file showing all available configuration options with explanations.

## Usage Examples

### Basic usage (uses config file defaults):
```bash
./build-custom-envoy.sh
```

### Override image tag:
```bash
./build-custom-envoy.sh v1.2.3
```

### Build only (don't push to ECR):
```bash
./build-custom-envoy.sh --no-push
```

### Force rebuild:
```bash
./build-custom-envoy.sh --force
```

### Build with cleanup:
```bash
./build-custom-envoy.sh --cleanup
```

## Key Features

✅ **All variables in config file** - No hardcoded values in script  
✅ **Command-line options** - Control build behavior without editing config  
✅ **Multi-tag support** - Can build and push multiple tags simultaneously  
✅ **Platform targeting** - Support for multi-architecture builds  
✅ **Validation** - Checks for required variables and files  
✅ **Error handling** - Proper exit codes and error messages  
✅ **Cleanup options** - Optional cleanup of local images  
✅ **Help documentation** - Built-in usage information  

## Configuration Options

All settings are now controlled via `build-config.env`:

- **AWS_REGION**: Target AWS region
- **AWS_PROFILE**: AWS CLI profile to use
- **ECR_REPOSITORY**: ECR repository name
- **DEFAULT_IMAGE_TAG**: Default tag when none specified
- **BASE_ENVOY_IMAGE**: Base Envoy image version
- **BUILD_PLATFORM**: Target platform (e.g., linux/amd64)
- **ADDITIONAL_TAGS**: Space-separated list of extra tags
- **CLEANUP_LOCAL_IMAGE**: Remove local image after push
- **ENABLE_SCANNING**: Enable ECR vulnerability scanning

## Benefits

1. **Consistency**: Same configuration across all builds
2. **Flexibility**: Easy to change settings without editing scripts
3. **Versioning**: Configuration can be version-controlled
4. **Documentation**: Clear examples and templates provided
5. **Maintenance**: Easier to update and maintain build process
