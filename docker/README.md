# OpenVidu2 HA Recorder Development Environment

A comprehensive development environment for building and testing OpenVidu recording images with MinIO S3 storage integration.

## 🎯 Project Overview

This project provides tools to replace the standard OpenVidu recording image with a custom NaevaTec version that supports HA (High Availability) recording functionality with S3-compatible storage backends.

### Key Features

- **Custom OpenVidu Recording Image**: Replace standard images with NaevaTec-enhanced versions
- **MinIO S3 Integration**: Local S3-compatible storage for development and testing
- **Environment Validation**: Comprehensive validation of configuration variables
- **Development Tools**: Helper scripts for managing the development workflow
- **Flexible Deployment**: Support for both local and S3 storage modes

## 📁 Project Structure

```
project/
├── data/                           # Persistent data storage
│   ├── minio/data/                # MinIO server data
│   └── recorder/data/             # Recording output files
├── scripts/                       # OpenVidu recorder scripts (mounted read-only)
├── utils/                         # Utility scripts (mounted read-only)
├── docker-compose.yml             # Multi-service orchestration
├── Dockerfile                     # Custom OpenVidu recording image
├── .env                          # Environment configuration
├── README.md                     # This documentation
├── replace-openvidu-image.sh     # Main deployment workflow
├── replace-openvidu-image-standalone.sh # Standalone image replacement
├── validate-env.sh               # Environment validation
└── manage-environment.sh         # Development helper tools
```

## ⚙️ Environment Configuration

The project uses a comprehensive `.env` file based on the OpenVidu2 HA Recorder specification:

### Required Variables

```bash
# Storage Configuration
HA_RECORDING_STORAGE=local          # 'local' or 's3'
CHUNK_FOLDER=/local-chunks           # Chunk storage folder
CHUNK_TIME_SIZE=20                   # Chunk duration in seconds

# S3/MinIO Configuration
HA_AWS_S3_SERVICE_ENDPOINT=http://172.31.0.96:9000  # MinIO endpoint
HA_AWS_S3_BUCKET=ov-recordings      # S3 bucket name
HA_AWS_ACCESS_KEY=naeva_minio        # MinIO credentials
HA_AWS_SECRET_KEY=N43v4t3c_M1n10    # MinIO credentials
MINIO_API_PORT=9000                  # MinIO API port
MINIO_CONSOLE_PORT=9001              # MinIO console port

# Docker Configuration
TAG=2.31.0                           # OpenVidu image tag
```

### Critical Requirements

⚠️ **Important**: `HA_AWS_S3_SERVICE_ENDPOINT` must match `http://YOUR_PRIVATE_IP:MINIO_API_PORT`

## 🐳 Docker Services

### Service Architecture

The project uses Docker Compose with the following services:

| Service              | Container Name             | Purpose                         | Network          |
| -------------------- | -------------------------- | ------------------------------- | ---------------- |
| `minio`              | `minio`                    | S3-compatible object storage    | `ov-ha-recorder` |
| `minio-mc`           | `minio-mc`                 | MinIO setup and bucket creation | `ov-ha-recorder` |
| `openvidu-recording` | `openvidu-recording-{TAG}` | Custom recording image          | `ov-ha-recorder` |

### Service Control

- **MinIO services**: Always available for development
- **Recorder service**: Uses profiles (`recorder`, `test`) - only starts when explicitly requested

### Volumes

- **MinIO data**: `./data/minio/data` (persistent storage)
- **Recording data**: `./data/recorder/data` (output files)
- **Scripts**: `./scripts` (read-only mount)
- **Utils**: `./utils` (read-only mount)

## 🚀 Usage Guide

### Quick Start

1. **Setup environment**:
   ```bash
   # Copy the provided .env template and customize
   # Update HA_AWS_S3_SERVICE_ENDPOINT with your private IP
   ```

2. **Validate configuration**:
   ```bash
   ./validate-env.sh
   ```

3. **Deploy everything**:
   ```bash
   ./replace-openvidu-image.sh 2.31.0
   ```

### Workflow Scripts

#### Main Deployment Script

**`./replace-openvidu-image.sh <TAG>`**

Complete deployment workflow:
1. ✅ Validates environment configuration
2. 🔍 Checks for existing OpenVidu images with old maintainer labels
3. 🗑️ Removes old images if found
4. 🔨 Builds new custom image with NaevaTec maintainer label
5. 🚀 Starts MinIO services
6. ✅ Verifies deployment success

```bash
./replace-openvidu-image.sh 2.31.0
```

#### Environment Validation

**`./validate-env.sh`**

Comprehensive environment validation:
- ✅ Checks all required variables exist
- ✅ Validates IP address format
- ✅ Ensures port number validity
- ✅ Verifies endpoint consistency
- ✅ Validates S3 bucket naming conventions
- 🔧 Offers auto-fix for common issues

```bash
./validate-env.sh
```

#### Development Helper

**`./manage-environment.sh [command] [TAG]`**

Development and testing utilities:

```bash
# Start MinIO services only
./manage-environment.sh start

# Check status of all services
./manage-environment.sh status

# Test container functionality
./manage-environment.sh test

# Full S3 recording test
./manage-environment.sh test-recorder

# View service logs
./manage-environment.sh logs

# Clean up everything
./manage-environment.sh clean

# Stop all services
./manage-environment.sh stop
```

#### Standalone Image Replacement

**`./replace-openvidu-image-standalone.sh <TAG>`**

Minimal image replacement without Docker Compose dependencies:
- 🔍 Checks and removes old images
- 🔨 Builds new image using direct Docker commands
- ✅ Validates maintainer labels

```bash
./replace-openvidu-image-standalone.sh 2.31.0
```

## 🧪 Testing

### Container Functionality Test

Tests basic container components:

```bash
./manage-environment.sh test
```

**What it tests**:
- Chrome browser installation
- FFmpeg availability
- xvfb-run-safe utility
- Recording directory access
- Environment variable passing

### Full Recording Test

Tests complete S3 recording workflow:

```bash
./manage-environment.sh test-recorder
```

**What it tests**:
- S3 connectivity to MinIO
- Bucket access and permissions
- Environment variable configuration
- Container startup and initialization
- Recording service functionality

### Manual Testing

Start recorder manually for custom testing:

```bash
# Start MinIO first
./manage-environment.sh start

# Start recorder with test profile
docker-compose --profile test up -d openvidu-recording

# Check logs
docker-compose logs openvidu-recording

# Stop recorder
docker-compose --profile test down
```

## 🔧 Troubleshooting

### Common Issues

#### Environment Validation Failures

**Issue**: `HA_AWS_S3_SERVICE_ENDPOINT` mismatch
```
❌ HA_AWS_S3_SERVICE_ENDPOINT inconsistency!
   Current: http://192.168.1.100:9000
   Expected: http://172.31.0.96:9000
```

**Solution**: Update your private IP in the endpoint or use auto-fix:
```bash
./validate-env.sh
# Choose 'y' when prompted to auto-fix
```

#### Container Start Failures

**Issue**: MinIO setup fails
```bash
# Check setup logs
docker-compose logs minio-mc

# Restart MinIO services
./manage-environment.sh stop
./manage-environment.sh start
```

**Issue**: Recorder fails to start
```bash
# Check if image exists
docker images openvidu/openvidu-recording:2.31.0

# Rebuild if necessary
./replace-openvidu-image.sh 2.31.0

# Check recorder logs
docker-compose logs openvidu-recording
```

#### Permission Issues

**Issue**: Local directories not accessible
```bash
# Create directories with proper permissions
mkdir -p ./data/minio/data ./data/recorder/data
chmod 755 ./data/minio/data ./data/recorder/data
```

### Service Access

- **MinIO Console**: http://localhost:9001
  - Username: `naeva_minio` (or your `HA_AWS_ACCESS_KEY`)
  - Password: `N43v4t3c_M1n10` (or your `HA_AWS_SECRET_KEY`)

- **MinIO API**: http://localhost:9000

### Log Analysis

```bash
# All services
docker-compose logs

# Specific service
docker-compose logs minio
docker-compose logs minio-mc
docker-compose logs openvidu-recording

# Follow logs in real-time
docker-compose logs -f openvidu-recording
```

## 🏗️ Image Building Details

### Custom Dockerfile

The project uses a custom Dockerfile based on Ubuntu 24.04 with:

- **Base packages**: Essential development tools
- **Chrome browser**: Latest stable version for recording
- **FFmpeg**: Video processing capabilities
- **PulseAudio**: Audio handling
- **Xvfb**: Virtual display server
- **Custom scripts**: Recording and utility scripts
- **NaevaTec maintainer label**: `"NaevaTec-OpenVidu eiglesia@openvidu.io"`

### Build Process

The build process automatically:
1. Removes images with old maintainer labels
2. Builds new image with your Dockerfile
3. Verifies correct maintainer label
4. Integrates with MinIO services

### Image Versioning

Images are tagged using the `TAG` environment variable:
- **Development**: Use version-specific tags (e.g., `2.31.0`)
- **Testing**: Can use `latest` for rapid iteration
- **Production**: Always use specific version tags

## 🔒 Security Considerations

### Development Environment

- Default credentials are provided for development convenience
- MinIO buckets are set to public for testing
- Services are exposed on localhost only

### Production Deployment

For production use:

1. **Change default credentials**:
   ```bash
   HA_AWS_ACCESS_KEY=your-secure-access-key
   HA_AWS_SECRET_KEY=your-secure-secret-key
   ```

2. **Use proper bucket policies**:
   - Remove public access
   - Implement least-privilege access

3. **Network security**:
   - Use private networks
   - Implement proper firewall rules
   - Consider TLS/SSL termination

## 📋 Development Workflow

### Typical Development Session

1. **Start development environment**:
   ```bash
   ./manage-environment.sh start
   ```

2. **Make changes to Dockerfile or scripts**

3. **Rebuild and test**:
   ```bash
   ./replace-openvidu-image.sh 2.31.0
   ```

4. **Test functionality**:
   ```bash
   ./manage-environment.sh test-recorder
   ```

5. **Clean up when done**:
   ```bash
   ./manage-environment.sh clean
   ```

### Iterative Development

For rapid iteration during development:

```bash
# Quick image rebuild without full deployment
./replace-openvidu-image-standalone.sh 2.31.0

# Test specific functionality
./manage-environment.sh test

# Start recorder for manual testing
docker-compose --profile test up -d openvidu-recording
```

## 🤝 Contributing

### Script Modifications

When modifying scripts:

1. **Test thoroughly** with `./validate-env.sh`
2. **Update documentation** in this README
3. **Maintain backward compatibility** where possible
4. **Follow existing naming conventions**

### Environment Variables

When adding new environment variables:

1. **Add to `.env` template**
2. **Update validation script**
3. **Document in this README**
4. **Update Docker Compose if needed**

## 📚 References

- [OpenVidu Documentation](https://docs.openvidu.io/)
- [MinIO Documentation](https://docs.min.io/)
- [NaevaTec OpenVidu Integration](https://github.com/naevatec/ov2-ha-recorder)
- [Docker Compose Profiles](https://docs.docker.com/compose/profiles/)

---

**NaevaTec - OpenVidu2 HA Recorder Development Environment**  
For support: info@naevatec.com