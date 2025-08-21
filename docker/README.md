# OpenVidu2 HA Recorder Development Environment

A comprehensive development environment for building and testing OpenVidu recording images with MinIO S3 storage integration and HA Controller session management.

## 🎯 Project Overview

This project provides tools to replace the standard OpenVidu recording image with a custom NaevaTec version that supports HA (High Availability) recording functionality with S3-compatible storage backends and centralized session management through an integrated HA Controller.

### Key Features

- **Custom OpenVidu Recording Image**: Replace standard images with NaevaTec-enhanced versions
- **HA Controller Integration**: SpringBoot-based session management with Redis storage
- **MinIO S3 Integration**: Local S3-compatible storage for development and testing
- **Session Management**: Real-time session tracking, heartbeat monitoring, and automatic cleanup
- **Environment Validation**: Comprehensive validation of configuration variables
- **Development Tools**: Helper scripts for managing the complete development workflow
- **Flexible Deployment**: Support for both local and S3 storage modes with optional HA Controller

## 📁 Project Structure

```
project/
├── src/                           # HA Controller source code
│   ├── main/
│   │   ├── java/
│   │   │   └── com/
│   │   │       └── naevatec/
│   │   │           └── ovrecorder/
│   │   │               ├── OvRecorderApplication.java    # Main SpringBoot application
│   │   │               ├── config/
│   │   │               │   ├── RedisConfig.java         # Redis configuration
│   │   │               │   └── SecurityConfig.java      # Security configuration
│   │   │               ├── controller/
│   │   │               │   └── SessionController.java   # REST API endpoints
│   │   │               ├── model/
│   │   │               │   └── RecordingSession.java   # Session data model
│   │   │               ├── repository/
│   │   │               │   └── SessionRepository.java  # Redis operations
│   │   │               └── service/
│   │   │                   └── SessionService.java     # Business logic
│   │   └── resources/
│   │       └── application.properties                  # Configuration file
├── server/                        # HA Controller build context
│   └── Dockerfile                 # HA Controller container build
├── recorder/                      # OpenVidu recording build context
│   ├── Dockerfile                 # OpenVidu recording container build
│   ├── scripts/                   # Recording scripts (mounted read-only)
│   └── utils/                     # Recording utilities (mounted read-only)
├── data/                          # Persistent data storage
│   ├── minio/data/               # MinIO server data
│   ├── redis/data/               # Redis session data
│   ├── controller/logs/          # HA Controller logs
│   └── recorder/data/            # Recording output files
├── docker-compose.yml            # Multi-service orchestration
├── pom.xml                       # Maven configuration for HA Controller
├── .env                         # Environment configuration
├── README.md                    # This documentation
├── replace-openvidu-image.sh    # Main deployment workflow
├── manage-environment.sh        # Development helper tools
├── validate-env.sh              # Environment validation
└── example-scripts.sh           # Shell script examples for HA Controller API
```

## ⚙️ Environment Configuration

The project uses a comprehensive `.env` file for both recording and HA Controller configuration:

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

# HA Controller Configuration
HA_RECORDER_USERNAME=recorder        # HA Controller API username
HA_RECORDER_PASSWORD=rec0rd3r_2024!  # HA Controller API password
HA_RECORDER_PORT=8080               # HA Controller external port
HA_SESSION_CLEANUP_INTERVAL=30000   # Session review frecuency in milliseconds
HA_SESSION_MAX_INACTIVE_TIME=600    # Max time before session cleanup

# Docker Configuration
TAG=2.31.0                          # OpenVidu image tag
```

### Critical Requirements

⚠️ **Important**: `HA_AWS_S3_SERVICE_ENDPOINT` must match `http://YOUR_PRIVATE_IP:MINIO_API_PORT`

## 🐳 Docker Services

### Service Architecture

The project uses Docker Compose v2 with the following services:

| Service                     | Container Name              | Purpose                         | Network          | External Access      |
| --------------------------- | --------------------------- | ------------------------------- | ---------------- | -------------------- |
| `minio`                     | `minio`                     | S3-compatible object storage    | `ov-ha-recorder` | :9000, :9001         |
| `minio-mc`                  | `minio-mc`                  | MinIO setup and bucket creation | `ov-ha-recorder` | None                 |
| `redis`                     | `ov-recorder-redis`         | Session data storage            | `ov-ha-recorder` | None (internal)      |
| `ov-recorder-ha-controller` | `ov-recorder-ha-controller` | Session management API          | `ov-ha-recorder` | :8080 (configurable) |
| `openvidu-recording`        | `openvidu-recording-{TAG}`  | Custom recording image          | `ov-ha-recorder` | None                 |

### Service Control

- **Infrastructure services**: MinIO, Redis, HA Controller - always available
- **Recorder service**: Uses profiles (`recorder`, `test`) - starts when explicitly requested
- **HA Controller**: Always included, provides session management API

### Volumes and Data Persistence

- **MinIO data**: `./data/minio/data` (persistent S3 storage)
- **Redis data**: `./data/redis/data` (persistent session storage)
- **Controller logs**: `./data/controller/logs` (HA Controller application logs)
- **Recording data**: `./data/recorder/data` (video output files)
- **Scripts**: `./recorder/scripts` (read-only mount)
- **Utils**: `./recorder/utils` (read-only mount)

## 🚀 Usage Guide

### Quick Start

1. **Setup environment**:
   ```bash
   # Copy the provided .env template and customize
   # Update HA_AWS_S3_SERVICE_ENDPOINT with your private IP
   # Configure HA Controller credentials
   ```

2. **Validate configuration**:
   ```bash
   ./validate-env.sh
   ```

3. **Deploy everything**:
   ```bash
   ./replace-openvidu-image.sh 2.31.0
   ```

4. **Test HA Controller**:
   ```bash
   curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/health
   ```

### Workflow Scripts

#### Main Deployment Script

**`./replace-openvidu-image.sh <TAG>`**

Complete deployment workflow with HA Controller integration:
1. ✅ Validates environment configuration
2. 📁 Creates all required directories (Redis, controller logs, etc.)
3. 🔨 Builds HA Controller (SpringBoot application)
4. 🔍 Checks for existing OpenVidu images with old maintainer labels
5. 🗑️ Removes old images if found
6. 🔨 Builds new custom OpenVidu recording image with NaevaTec maintainer label
7. 🚀 Starts MinIO services and waits for setup completion
8. 🚀 Starts Redis service for session storage
9. 🚀 Starts HA Controller and waits for readiness
10. 🧪 Tests HA Controller API functionality
11. ✅ Verifies complete deployment success

```bash
./replace-openvidu-image.sh 2.31.0
```

#### Environment Validation

**`./validate-env.sh`**

Comprehensive environment validation including HA Controller settings:
- ✅ Checks all required variables exist
- ✅ Validates IP address format
- ✅ Ensures port number validity
- ✅ Verifies endpoint consistency
- ✅ Validates S3 bucket naming conventions
- ✅ Checks HA Controller configuration
- 🔧 Offers auto-fix for common issues

```bash
./validate-env.sh
```

#### Development Helper

**`./manage-environment.sh [command] [TAG]`**

Development and testing utilities with full HA Controller support:

```bash
# Start complete environment (MinIO + Redis + HA Controller)
./manage-environment.sh start

# Check status of all services including HA Controller
./manage-environment.sh status

# Test OpenVidu container functionality
./manage-environment.sh test

# Test HA Controller API comprehensively
./manage-environment.sh test-ha

# Full S3 recording test with HA Controller integration
./manage-environment.sh test-recorder

# View logs from all services
./manage-environment.sh logs

# Clean up everything including HA Controller data
./manage-environment.sh clean

# Stop all services
./manage-environment.sh stop
```

## 📡 HA Controller API

The integrated HA Controller provides a comprehensive REST API for session management:

### Authentication

All API endpoints require HTTP Basic Authentication:
- **Username**: `recorder` (configurable via `HA_RECORDER_USERNAME`)
- **Password**: `rec0rd3r_2024!` (configurable via `HA_RECORDER_PASSWORD`)

### API Endpoints

#### Session Management

| Method   | Endpoint                       | Description                  |
| -------- | ------------------------------ | ---------------------------- |
| `POST`   | `/api/sessions`                | Create new recording session |
| `GET`    | `/api/sessions`                | List all active sessions     |
| `GET`    | `/api/sessions/{id}`           | Get session by ID            |
| `PUT`    | `/api/sessions/{id}/heartbeat` | Update session heartbeat     |
| `PUT`    | `/api/sessions/{id}/status`    | Update session status        |
| `PUT`    | `/api/sessions/{id}/path`      | Update recording path        |
| `PUT`    | `/api/sessions/{id}/stop`      | Stop session                 |
| `DELETE` | `/api/sessions/{id}`           | Remove session               |
| `GET`    | `/api/sessions/{id}/active`    | Check if session is active   |

#### Maintenance

| Method | Endpoint                | Description                         |
| ------ | ----------------------- | ----------------------------------- |
| `POST` | `/api/sessions/cleanup` | Manual cleanup of inactive sessions |
| `GET`  | `/api/sessions/health`  | Service health check                |

### API Usage Examples

#### Create a Recording Session
```bash
curl -u recorder:rec0rd3r_2024! -X POST \
  http://localhost:8080/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "rec-001",
    "clientId": "camera-01",
    "clientHost": "192.168.1.100"
  }'
```

#### Send Heartbeat
```bash
curl -u recorder:rec0rd3r_2024! -X PUT \
  http://localhost:8080/api/sessions/rec-001/heartbeat
```

#### Update Session Status
```bash
curl -u recorder:rec0rd3r_2024! -X PUT \
  http://localhost:8080/api/sessions/rec-001/status \
  -H "Content-Type: application/json" \
  -d '{"status": "RECORDING"}'
```

#### List All Sessions
```bash
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions
```

### Shell Script Integration

The project includes `example-scripts.sh` with ready-to-use functions for shell script integration:

```bash
# Make script executable
chmod +x example-scripts.sh

# Create session
./example-scripts.sh create rec-001 camera-01

# Send heartbeat
./example-scripts.sh heartbeat rec-001

# Update status
./example-scripts.sh status rec-001 RECORDING

# Keep session alive automatically
./example-scripts.sh keep-alive rec-001 30
```

## 🧪 Testing

### Container Functionality Test

Tests basic OpenVidu container components:

```bash
./manage-environment.sh test
```

**What it tests**:
- Chrome browser installation
- FFmpeg availability
- xvfb-run-safe utility
- Recording directory access
- Environment variable passing
- HA Controller connectivity

### HA Controller API Test

Tests complete HA Controller functionality:

```bash
./manage-environment.sh test-ha
```

**What it tests**:
- Health endpoint accessibility
- Authentication mechanisms
- Session creation and retrieval
- Heartbeat functionality
- Session cleanup
- API response validation

### Full Recording Test

Tests complete S3 recording workflow with HA Controller:

```bash
./manage-environment.sh test-recorder
```

**What it tests**:
- S3 connectivity to MinIO
- Bucket access and permissions
- HA Controller session registration
- Environment variable configuration
- Container startup and initialization
- Recording service functionality
- Session management integration

### Manual Testing

Start services manually for custom testing:

```bash
# Start complete environment
./manage-environment.sh start

# Start recorder with test profile
docker compose --profile test up -d openvidu-recording

# Check all service logs
docker compose logs

# Test HA Controller API manually
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/health

# Stop recorder only
docker compose --profile test down
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

#### HA Controller Issues

**Issue**: HA Controller fails to start
```bash
# Check if Redis is running
docker compose ps redis

# Check HA Controller logs
docker compose logs ov-recorder-ha-controller

# Rebuild HA Controller
docker compose build ov-recorder-ha-controller
docker compose up -d ov-recorder-ha-controller
```

**Issue**: HA Controller API not responding
```bash
# Test basic connectivity
curl -f http://localhost:8080/actuator/health

# Test authenticated endpoint
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/health

# Check port configuration
echo $HA_RECORDER_PORT
```

#### Container Start Failures

**Issue**: MinIO setup fails
```bash
# Check setup logs
docker compose logs minio-mc

# Restart MinIO services
./manage-environment.sh stop
./manage-environment.sh start
```

**Issue**: Redis connection fails
```bash
# Check Redis logs
docker compose logs redis

# Check Redis data directory permissions
ls -la ./data/redis/data

# Restart Redis
docker compose restart redis
```

**Issue**: Recorder fails to start
```bash
# Check if images exist
docker images openvidu/openvidu-recording:2.31.0
docker images | grep ov-recorder-ha-controller

# Rebuild if necessary
./replace-openvidu-image.sh 2.31.0

# Check recorder logs
docker compose logs openvidu-recording
```

#### Permission Issues

**Issue**: Local directories not accessible
```bash
# Create directories with proper permissions
mkdir -p ./data/minio/data ./data/redis/data ./data/controller/logs ./data/recorder/data
chmod 755 ./data/minio/data ./data/redis/data ./data/controller/logs ./data/recorder/data
```

### Service Access

- **MinIO Console**: http://localhost:9001
  - Username: `naeva_minio` (or your `HA_AWS_ACCESS_KEY`)
  - Password: `N43v4t3c_M1n10` (or your `HA_AWS_SECRET_KEY`)

- **MinIO API**: http://localhost:9000

- **HA Controller API**: http://localhost:8080/api/sessions
  - Username: `recorder` (or your `HA_RECORDER_USERNAME`)
  - Password: `rec0rd3r_2024!` (or your `HA_RECORDER_PASSWORD`)

- **HA Controller Health**: http://localhost:8080/actuator/health

### Log Analysis

```bash
# All services
docker compose logs

# Specific services
docker compose logs minio
docker compose logs redis
docker compose logs ov-recorder-ha-controller
docker compose logs openvidu-recording

# Follow logs in real-time
docker compose logs -f ov-recorder-ha-controller

# Filter HA Controller logs
docker compose logs ov-recorder-ha-controller | grep ERROR
```

## 🗃️ HA Controller Source Code

### SpringBoot Application Structure

The HA Controller is a complete SpringBoot application with the following components:

#### Main Application
- **`OvRecorderApplication.java`**: Main SpringBoot application with scheduling enabled

#### Configuration
- **`RedisConfig.java`**: Redis connection and serialization configuration
- **`SecurityConfig.java`**: HTTP Basic Authentication setup

#### Data Model
- **`RecordingSession.java`**: Complete session model with JSON serialization
  - Session metadata (ID, client info, timestamps)
  - Status management (STARTING, RECORDING, PAUSED, STOPPED, etc.)
  - Heartbeat functionality
  - Recording path tracking

#### Data Access
- **`SessionRepository.java`**: Redis operations wrapper
  - Session CRUD operations
  - Automatic expiration handling
  - Bulk operations for cleanup
  - Orphaned session detection

#### Business Logic
- **`SessionService.java`**: Core business logic
  - Session lifecycle management
  - Automatic cleanup scheduling
  - Heartbeat processing
  - Status transitions

#### REST API
- **`SessionController.java`**: Complete REST API implementation
  - All CRUD endpoints
  - Authentication integration
  - Error handling
  - Request/response DTOs

### Development with HA Controller Source

#### Local Development Setup

1. **IDE Setup** (VSCode/IntelliJ):
   ```bash
   # Import Maven project from root directory
   # Ensure Java 17+ is configured
   # Run OvRecorderApplication.java directly for development
   ```

2. **Maven Commands**:
   ```bash
   # Build application
   mvn clean package

   # Run tests
   mvn test

   # Run application locally
   mvn spring-boot:run
   ```

3. **Docker Development**:
   ```bash
   # Build only HA Controller
   docker compose build ov-recorder-ha-controller

   # Start dependencies (Redis)
   docker compose up -d redis

   # Start HA Controller
   docker compose up -d ov-recorder-ha-controller
   ```

#### Source Code Modifications

When modifying the HA Controller source:

1. **Code Changes**: Edit files in `src/main/java/com/naevatec/ovrecorder/`
2. **Configuration**: Update `src/main/resources/application.properties`
3. **Build**: Use Maven to build the application
4. **Deploy**: Use Docker Compose to deploy updated container

```bash
# After making changes
mvn clean package
docker compose build ov-recorder-ha-controller
docker compose up -d ov-recorder-ha-controller
```

## 🗃️ Image Building Details

### Custom Dockerfiles

The project uses two separate Dockerfiles:

#### HA Controller (`server/Dockerfile`)
- **Base**: OpenJDK 17 with multi-stage build
- **Build Stage**: Maven build with dependency caching
- **Runtime Stage**: Lightweight JRE with security hardening
- **Features**: Health checks, non-root user, proper logging

#### OpenVidu Recording (`recorder/Dockerfile`)
- **Base**: Ubuntu 24.04 or existing OpenVidu image
- **Components**: Chrome, FFmpeg, PulseAudio, Xvfb
- **Integration**: HA Controller connectivity
- **Scripts**: Custom recording and utility scripts
- **Maintainer**: `"NaevaTec-OpenVidu eiglesia@openvidu.io"`

### Build Process

The build process automatically:
1. Builds HA Controller from source using Maven
2. Removes images with old maintainer labels
3. Builds new OpenVidu recording image with integration
4. Verifies correct maintainer labels
5. Integrates all services with MinIO and Redis

### Image Versioning

Images are tagged using the `TAG` environment variable:
- **HA Controller**: Uses project version from `pom.xml`
- **OpenVidu Recording**: Uses `TAG` environment variable
- **Development**: Use version-specific tags (e.g., `2.31.0`)
- **Testing**: Can use `latest` for rapid iteration
- **Production**: Always use specific version tags

## 🔒 Security Considerations

### Development Environment

- Default credentials are provided for development convenience
- MinIO buckets are set to public for testing
- Services are exposed on localhost only
- Redis has no authentication (internal network only)
- HA Controller uses HTTP Basic Auth

### Production Deployment

For production use:

1. **Change default credentials**:
   ```bash
   HA_AWS_ACCESS_KEY=your-secure-access-key
   HA_AWS_SECRET_KEY=your-secure-secret-key
   HA_RECORDER_USERNAME=your-secure-username
   HA_RECORDER_PASSWORD=your-very-secure-password
   ```

2. **Secure Redis**:
   - Enable Redis AUTH
   - Use Redis over TLS
   - Restrict network access

3. **HA Controller Security**:
   - Use HTTPS with SSL certificates
   - Implement JWT tokens instead of Basic Auth
   - Add rate limiting and request validation

4. **Use proper bucket policies**:
   - Remove public access
   - Implement least-privilege access

5. **Network security**:
   - Use private networks
   - Implement proper firewall rules
   - Consider TLS/SSL termination

## 📋 Development Workflow

### Typical Development Session

1. **Start development environment**:
   ```bash
   ./manage-environment.sh start
   ```

2. **Make changes to source code, Dockerfiles, or scripts**

3. **Test HA Controller locally** (optional):
   ```bash
   mvn spring-boot:run
   # Test on http://localhost:8080
   ```

4. **Rebuild and deploy**:
   ```bash
   ./replace-openvidu-image.sh 2.31.0
   ```

5. **Test complete functionality**:
   ```bash
   ./manage-environment.sh test-ha
   ./manage-environment.sh test-recorder
   ```

6. **Clean up when done**:
   ```bash
   ./manage-environment.sh clean
   ```

### Iterative Development

For rapid iteration during development:

```bash
# HA Controller only changes
mvn clean package
docker compose build ov-recorder-ha-controller
docker compose restart ov-recorder-ha-controller

# OpenVidu recording changes
docker compose build openvidu-recording

# Test specific functionality
./manage-environment.sh test
./manage-environment.sh test-ha

# Start recorder for manual testing
docker compose --profile test up -d openvidu-recording
```

### Integration Testing

```bash
# Full integration test
./replace-openvidu-image.sh 2.31.0
./manage-environment.sh test-ha
./manage-environment.sh test-recorder

# Manual session management test
./example-scripts.sh create test-session client-01
./example-scripts.sh heartbeat test-session
./example-scripts.sh status test-session RECORDING
./example-scripts.sh stop test-session
```

## 🤝 Contributing

### Script Modifications

When modifying scripts:

1. **Test thoroughly** with `./validate-env.sh`
2. **Update documentation** in this README
3. **Maintain backward compatibility** where possible
4. **Follow existing naming conventions**
5. **Test with both development and production configurations**

### HA Controller Development

When modifying HA Controller source:

1. **Follow SpringBoot best practices**
2. **Maintain API compatibility**
3. **Add comprehensive tests**
4. **Update API documentation**
5. **Test with real Redis instances**

### Environment Variables

When adding new environment variables:

1. **Add to `.env` template**
2. **Update validation script**
3. **Document in this README**
4. **Update Docker Compose if needed**
5. **Add to HA Controller configuration if applicable**

## 📚 References

- [OpenVidu Documentation](https://docs.openvidu.io/)
- [MinIO Documentation](https://docs.min.io/)
- [SpringBoot Documentation](https://spring.io/projects/spring-boot)
- [Redis Documentation](https://redis.io/documentation)
- [NaevaTec OpenVidu Integration](https://github.com/naevatec/ov2-ha-recorder)
- [Docker Compose Profiles](https://docs.docker.com/compose/profiles/)

---

**NaevaTec - OpenVidu2 HA Recorder Development Environment with HA Controller**  
For support: info@naevatec.com
