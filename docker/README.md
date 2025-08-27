# OpenVidu2 HA Recorder Development Environment

A comprehensive development environment for building and testing OpenVidu recording images with MinIO S3 storage integration and HA Controller session management.

## 🎯 Project Overview

This project provides tools to replace the standard OpenVidu recording image with a custom NaevaTec version that supports HA (High Availability) recording functionality with S3-compatible storage backends and centralized session management through an integrated HA Controller with real-time chunk tracking and heartbeat monitoring.

### Key Features

- **Custom OpenVidu Recording Image**: Replace standard images with NaevaTec-enhanced versions
- **HA Controller Integration**: SpringBoot-based session management with Redis storage
- **Real-time Chunk Tracking**: Monitor recording progress with chunk-level precision
- **Simplified Session Management**: Registration, heartbeats with chunk info, and deregistration only
- **MinIO S3 Integration**: Local S3-compatible storage for development and testing
- **Swagger API Documentation**: Interactive API documentation with profile-based access control
- **Session Heartbeat Monitoring**: Automatic heartbeat with last chunk information
- **Environment Validation**: Comprehensive validation of configuration variables
- **Development Tools**: Helper scripts for managing the complete development workflow
- **Fast Container Shutdown**: Optimized for 30-second container deadline compliance

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
│   │   │               │   ├── SecurityConfig.java      # Security configuration
│   │   │               │   └── SwaggerConfig.java       # Swagger/OpenAPI configuration
│   │   │               ├── controller/
│   │   │               │   └── SessionController.java   # Simplified REST API endpoints
│   │   │               ├── model/
│   │   │               │   └── RecordingSession.java   # Session data model with chunk tracking
│   │   │               ├── repository/
│   │   │               │   └── SessionRepository.java  # Redis operations
│   │   │               └── service/
│   │   │                   └── SessionService.java     # Business logic
│   │   └── resources/
│   │       ├── application.properties                  # Main configuration
│   │       ├── application-dev.properties             # Development profile
│   │       ├── application-test.properties            # Test profile
│   │       └── application-prod.properties            # Production profile
├── server/                        # HA Controller build context
│   └── Dockerfile                 # HA Controller container build
├── recorder/                      # OpenVidu recording build context
│   ├── Dockerfile                 # OpenVidu recording container build
│   ├── scripts/                   # Recording scripts (mounted read-only)
│   │   ├── composed.sh           # Enhanced main recording script with HA integration
│   │   ├── session-register.sh   # Session registration script
│   │   └── recorder-session-manager.sh  # Background heartbeat and chunk tracking
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
HA_CONTROLLER_HOST=ov-recorder          # HA Controller hostname (usually service name)
HA_CONTROLLER_PORT=8080                 # HA Controller port
HA_CONTROLLER_USERNAME=recorder       # HA Controller API username
HA_CONTROLLER_PASSWORD=rec0rd3r_2024! # HA Controller API password
HEARTBEAT_INTERVAL=10                # Heartbeat interval in seconds
RECORDING_BASE_URL=https://devel.naevatec.com:4443/openvidu  # Base URL for recordings

# HA Controller Internal Configuration
HA_CONTROLLER_PORT=8080               # HA Controller external port
HA_SESSION_CLEANUP_INTERVAL=30000   # Session review frequency in milliseconds
HA_SESSION_MAX_INACTIVE_TIME=600    # Max time before session cleanup

# Docker Configuration
IMAGE_TAG=2.31.0                          # OpenVidu image tag

# Swagger Configuration (Profile-based)
SPRING_PROFILES_ACTIVE=dev          # 'dev', 'test', or 'prod'
SWAGGER_ENABLED=true                # Enable/disable Swagger (auto-disabled in prod)
SWAGGER_UI_ENABLED=true             # Enable/disable Swagger UI
```

### Critical Requirements

⚠️ **Important**: 
- `HA_AWS_S3_SERVICE_ENDPOINT` must match `http://YOUR_PRIVATE_IP:MINIO_API_PORT`
- `HA_CONTROLLER_HOST` should match the Docker service name (`ov-recorder`)
- `HA_CONTROLLER_USERNAME` and `HA_CONTROLLER_PASSWORD` must match between recorder and HA Controller

## 🐳 Docker Services

### Service Architecture

The project uses Docker Compose v2 with the following services:

| Service                     | Container Name              | Purpose                         | Network          | External Access      |
| --------------------------- | --------------------------- | ------------------------------- | ---------------- | -------------------- |
| `minio`                     | `minio`                     | S3-compatible object storage    | `ov-ha-recorder` | :9000, :9001         |
| `minio-mc`                  | `minio-mc`                  | MinIO setup and bucket creation | `ov-ha-recorder` | None                 |
| `redis`                     | `ov-recorder-redis`         | Session data storage            | `ov-ha-recorder` | None (internal)      |
| `ov-recorder-ha-controller` | `ov-recorder-ha-controller` | Session management API          | `ov-ha-recorder` | :8080 (configurable) |
| `openvidu-recording`        | `openvidu-recording-{IMAGE_TAG}`  | Custom recording image          | `ov-ha-recorder` | None                 |

### Service Control

- **Infrastructure services**: MinIO, Redis, HA Controller - always available
- **Recorder service**: Uses profiles (`recorder`, `test`) - starts when explicitly requested
- **HA Controller**: Always included, provides session management API with Swagger documentation

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
   # Set HA_CONTROLLER_HOST to match your Docker service name
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

5. **Access Swagger Documentation** (development/test only):
   ```bash
   # Open browser to: http://localhost:8080/swagger-ui.html
   # Swagger is automatically disabled in production profile
   ```

### Workflow Scripts

#### Main Deployment Script

**`./replace-openvidu-image.sh <IMAGE_TAG>`**

Complete deployment workflow with HA Controller integration:
1. ✅ Validates environment configuration including HA Controller settings
2. 🗂 Creates all required directories (Redis, controller logs, etc.)
3. 🔨 Builds HA Controller (SpringBoot application with Maven)
4. 🔍 Checks for existing OpenVidu images with old maintainer labels
5. 🗑️ Removes old images if found
6. 🔨 Builds new custom OpenVidu recording image with HA integration scripts
7. 🚀 Starts MinIO services and waits for setup completion
8. 🚀 Starts Redis service for session storage
9. 🚀 Starts HA Controller and waits for readiness
10. 🧪 Tests HA Controller API functionality
11. 📖 Verifies Swagger documentation accessibility (dev/test profiles)
12. ✅ Verifies complete deployment success

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
- ✅ Validates authentication credentials
- ✅ Verifies heartbeat interval settings
- 🔧 Offers auto-fix for common issues

```bash
./validate-env.sh
```

#### Development Helper

**`./manage-environment.sh [command] [IMAGE_TAG]`**

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

The integrated HA Controller provides a simplified REST API for essential session management with real-time chunk tracking:

### Authentication

All API endpoints require HTTP Basic Authentication:
- **Username**: `recorder` (configurable via `HA_CONTROLLER_USERNAME`)
- **Password**: `rec0rd3r_2024!` (configurable via `HA_CONTROLLER_PASSWORD`)

### Simplified API Design

The HA Controller uses a streamlined approach focusing on essential operations:

1. **Session Registration** - Register new recording sessions
2. **Heartbeat with Chunk Tracking** - Send heartbeats with last chunk information
3. **Session Deregistration** - Clean removal of completed sessions

### Core API Endpoints

#### Essential Session Management

| Method   | Endpoint                       | Description                                    |
| -------- | ------------------------------ | ---------------------------------------------- |
| `POST`   | `/api/sessions`                | Create new recording session (registration)    |
| `GET`    | `/api/sessions`                | List all active sessions                       |
| `GET`    | `/api/sessions/{id}`           | Get session by ID                              |
| `PUT`    | `/api/sessions/{id}/heartbeat` | Update session heartbeat with chunk info      |
| `DELETE` | `/api/sessions/{id}`           | Remove session (deregistration)               |
| `GET`    | `/api/sessions/{id}/active`    | Check if session is active                     |

#### Maintenance & Monitoring

| Method | Endpoint                | Description                         |
| ------ | ----------------------- | ----------------------------------- |
| `POST` | `/api/sessions/cleanup` | Manual cleanup of inactive sessions |
| `GET`  | `/api/sessions/health`  | Service health check                |

### API Usage Examples

#### Register a Recording Session
```bash
curl -u recorder:rec0rd3r_2024! -X POST \
  http://localhost:8080/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "eiglesia07_1755710237963",
    "clientId": "recorder-container01",
    "clientHost": "192.168.1.100",
    "metadata": "{\"id\":\"eiglesia07\",\"status\":\"started\",\"outputMode\":\"COMPOSED\"}"
  }'
```

#### Send Heartbeat with Chunk Information
```bash
# Heartbeat with new chunk
curl -u recorder:rec0rd3r_2024! -X PUT \
  http://localhost:8080/api/sessions/eiglesia07_1755710237963/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"lastChunk": "0003.mp4"}'

# Simple heartbeat (no new chunks)
curl -u recorder:rec0rd3r_2024! -X PUT \
  http://localhost:8080/api/sessions/eiglesia07_1755710237963/heartbeat
```

#### Deregister Session
```bash
curl -u recorder:rec0rd3r_2024! -X DELETE \
  http://localhost:8080/api/sessions/eiglesia07_1755710237963
```

#### List All Sessions
```bash
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions
```

### Session Data Model

Sessions include comprehensive tracking information:

```json
{
  "sessionId": "eiglesia07_1755710237963",
  "clientId": "recorder-container01",
  "clientHost": "192.168.1.100",
  "status": "RECORDING",
  "createdAt": "2024-01-20 10:00:00",
  "lastHeartbeat": "2024-01-20 10:30:00",
  "lastChunk": "0003.mp4",
  "recordingPath": null,
  "metadata": "{\"id\":\"eiglesia07\",\"status\":\"started\"}"
}
```

### Swagger Documentation

Interactive API documentation is available in development and test environments:

- **URL**: http://localhost:8080/swagger-ui.html
- **Profiles**: Enabled in `dev` and `test`, disabled in `prod`
- **Authentication**: Use the "Authorize" button with your credentials
- **Features**: 
  - Interactive API testing
  - Request/response examples
  - Schema documentation
  - Authentication testing

## 🔧 HA Integration in Recording Container

### Recorder Scripts Integration

The recording container includes integrated HA Controller session management:

#### Core Scripts

1. **`session-register.sh`** - Quick session registration
   - Extracts session info from recording metadata JSON
   - Registers with HA Controller
   - Exits immediately after registration

2. **`recorder-session-manager.sh`** - Background heartbeat manager
   - Monitors chunk directory for new .mp4 files
   - Sends heartbeat with chunk information when new chunks detected
   - Runs continuously in background during recording
   - Handles graceful termination

3. **`composed.sh`** - Enhanced main recording script
   - Integrated HA Controller session lifecycle management
   - Optimized for 30-second container shutdown deadline
   - Background HA operations to avoid blocking recording

### Integration Timeline

```
T+0s    📝 Create recording JSON metadata
T+1s    🔗 Register session with HA Controller (background)
T+2s    💓 Start heartbeat manager with chunk monitoring (background)
T+3s    🎬 Start Chrome and FFmpeg recording
...     💗 Send heartbeats every 30s with chunk progression
T+180s  🛑 FFmpeg stops, recording complete
T+181s  🧹 Terminate heartbeat manager (immediate)
T+182s  🗑️ Deregister session from HA Controller (background)
T+183s  🖼️ Generate thumbnail (priority task)
T+185s  🔒 Update permissions (priority task)
T+190s  ✅ Container exits within 30-second deadline
```

### Environment Variables in Recorder Container

Add these to `/recordings/.env` in the recorder container:

```bash
# HA Controller Connection (REQUIRED)
HA_CONTROLLER_HOST=ov-recorder
HA_CONTROLLER_PORT=8080

# HA Controller Authentication (REQUIRED)
HA_CONTROLLER_USERNAME=recorder
HA_CONTROLLER_PASSWORD=rec0rd3r_2024!

# Heartbeat Configuration (OPTIONAL - has defaults)
HEARTBEAT_INTERVAL=10

# Recording Base URL (OPTIONAL)
RECORDING_BASE_URL=https://devel.naevatec.com:4443/openvidu
```

### Chunk Tracking Features

- **Real-time Monitoring**: Detects new .mp4 chunks as they're created
- **Smart Updates**: Only sends chunk info when NEW chunks detected
- **Timestamp-based Detection**: Uses file modification times for accuracy
- **Background Processing**: Non-blocking chunk monitoring
- **Failover Data**: Provides chunk progression for HA failover logic

## 🧪 Testing

### Container Functionality Test

Tests basic OpenVidu container components with HA integration:

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
- Session registration scripts
- Heartbeat functionality

### HA Controller API Test

Tests complete HA Controller functionality including chunk tracking:

```bash
./manage-environment.sh test-ha
```

**What it tests**:
- Health endpoint accessibility
- Authentication mechanisms
- Session creation and retrieval
- Heartbeat functionality with chunk data
- Session deregistration
- API response validation
- Swagger documentation (dev/test profiles)
- Profile-based feature enabling/disabling

### Full Recording Test

Tests complete S3 recording workflow with HA Controller integration:

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
- Chunk tracking and heartbeat progression

### Manual Testing with Swagger

1. **Start development environment**:
   ```bash
   ./manage-environment.sh start
   ```

2. **Access Swagger UI**: http://localhost:8080/swagger-ui.html

3. **Authenticate**: Click "Authorize" button, enter credentials

4. **Test endpoints**:
   - Create session with POST `/api/sessions`
   - Send heartbeat with PUT `/api/sessions/{id}/heartbeat`
   - Monitor session with GET `/api/sessions/{id}`
   - Clean up with DELETE `/api/sessions/{id}`

### Manual Session Management Testing

```bash
# Test session lifecycle
curl -u recorder:rec0rd3r_2024! -X POST http://localhost:8080/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"sessionId":"test-001","clientId":"test-client","clientHost":"localhost"}'

# Test chunk tracking
curl -u recorder:rec0rd3r_2024! -X PUT http://localhost:8080/api/sessions/test-001/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"lastChunk":"0001.mp4"}'

# Verify session data
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/test-001

# Clean up
curl -u recorder:rec0rd3r_2024! -X DELETE http://localhost:8080/api/sessions/test-001
```

## 🔧 Troubleshooting

### Common Issues

#### Environment Validation Failures

**Issue**: `HA_CONTROLLER_HOST` not accessible
```
✖ HA Controller not accessible at ov-recorder:8080
```

**Solution**: Verify Docker service is running and ports are correct:
```bash
docker compose ps ov-recorder-ha-controller
docker compose logs ov-recorder-ha-controller
```

**Issue**: `HA_AWS_S3_SERVICE_ENDPOINT` mismatch
```
✖ HA_AWS_S3_SERVICE_ENDPOINT inconsistency!
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

# Check Maven build
mvn clean package

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
echo $CONTROLLER_PORT
```

**Issue**: Swagger not accessible
```bash
# Check profile setting
echo $SPRING_PROFILES_ACTIVE

# Swagger should be disabled in production
curl http://localhost:8080/swagger-ui.html
# Expected: 404 in prod profile, 200 in dev/test profiles
```

#### Session Management Issues

**Issue**: Session registration fails
```bash
# Check recorder container logs
docker compose logs openvidu-recording | grep "HA-REG"

# Test manual registration
curl -u recorder:rec0rd3r_2024! -X POST http://localhost:8080/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"sessionId":"test","clientId":"test","clientHost":"test"}'
```

**Issue**: Heartbeat failures
```bash
# Check heartbeat manager logs
docker compose logs openvidu-recording | grep "recorder-session-manager"

# Verify chunk directory exists
docker compose exec openvidu-recording ls -la /recordings/*/chunks/

# Test manual heartbeat
curl -u recorder:rec0rd3r_2024! -X PUT http://localhost:8080/api/sessions/test/heartbeat
```

#### Container Shutdown Issues

**Issue**: Container doesn't exit within 30 seconds
```bash
# Check if HA processes are hanging
docker compose logs openvidu-recording | grep "HA-CLEANUP"

# Verify quick cleanup implementation
docker compose exec openvidu-recording ps aux | grep session-manager

# Check for stuck curl processes
docker compose exec openvidu-recording ps aux | grep curl
```

#### Chunk Tracking Issues

**Issue**: Chunk information not updating
```bash
# Check chunk directory permissions
docker compose exec openvidu-recording ls -la /recordings/*/chunks/

# Verify chunk detection logic
docker compose logs openvidu-recording | grep "lastChunk"

# Test chunk directory manually
docker compose exec openvidu-recording find /recordings/*/chunks/ -name "*.mp4" -printf '%T@ %p\n' | sort -n
```

### Service Access

- **MinIO Console**: http://localhost:9001
  - Username: `naeva_minio` (or your `HA_AWS_ACCESS_KEY`)
  - Password: `N43v4t3c_M1n10` (or your `HA_AWS_SECRET_KEY`)

- **MinIO API**: http://localhost:9000

- **HA Controller API**: http://localhost:8080/api/sessions
  - Username: `recorder` (or your `HA_CONTROLLER_USERNAME`)
  - Password: `rec0rd3r_2024!` (or your `HA_CONTROLLER_PASSWORD`)

- **HA Controller Health**: http://localhost:8080/actuator/health

- **Swagger UI**: http://localhost:8080/swagger-ui.html (dev/test profiles only)

### Log Analysis

```bash
# All services
docker compose logs

# HA Controller specific
docker compose logs ov-recorder-ha-controller

# Recording container HA integration
docker compose logs openvidu-recording | grep -E "\[HA-|session-register|recorder-session-manager"

# Follow HA Controller logs in real-time
docker compose logs -f ov-recorder-ha-controller

# Filter HA Controller errors
docker compose logs ov-recorder-ha-controller | grep ERROR

# Check session registration process
docker compose logs openvidu-recording | grep "HA-REG"

# Monitor chunk tracking
docker compose logs openvidu-recording | grep "lastChunk"
```

## 🏗️ HA Controller Source Code

### SpringBoot Application Structure

The HA Controller is a complete SpringBoot application with the following components:

#### Main Application
- **`OvRecorderApplication.java`**: Main SpringBoot application with scheduling enabled

#### Configuration
- **`RedisConfig.java`**: Redis connection and serialization configuration
- **`SecurityConfig.java`**: HTTP Basic Authentication with Swagger endpoint access
- **`SwaggerConfig.java`**: Profile-based Swagger/OpenAPI configuration

#### Data Model
- **`RecordingSession.java`**: Complete session model with JSON serialization
  - Session metadata (ID, client info, timestamps)
  - Status management (STARTING, RECORDING, PAUSED, STOPPED, etc.)
  - Heartbeat functionality with chunk tracking
  - Recording path tracking
  - **New**: `lastChunk` field for chunk progression monitoring

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
  - **Enhanced**: Heartbeat processing with chunk information
  - Status transitions

#### REST API
- **`SessionController.java`**: Simplified REST API implementation
  - **Streamlined**: Focus on essential operations only
  - Registration, heartbeat with chunks, deregistration
  - Authentication integration
  - Error handling
  - Comprehensive Swagger documentation

### Development with HA Controller Source

#### Local Development Setup

1. **IDE Setup** (VSCode/IntelliJ):
   ```bash
   # Import Maven project from root directory
   # Ensure Java 17+ is configured
   # Set active profile: -Dspring.profiles.active=dev
   # Run OvRecorderApplication.java directly for development
   ```

2. **Maven Commands**:
   ```bash
   # Build application
   mvn clean package

   # Run tests
   mvn test

   # Run application locally (development profile)
   mvn spring-boot:run -Dspring-boot.run.profiles=dev

   # Run with specific profile
   mvn spring-boot:run -Dspring-boot.run.profiles=test
   ```

3. **Docker Development**:
   ```bash
   # Build only HA Controller
   docker compose build ov-recorder-ha-controller

   # Start dependencies (Redis)
   docker compose up -d redis

   # Start HA Controller with development profile
   SPRING_PROFILES_ACTIVE=dev docker compose up -d ov-recorder-ha-controller
   ```

#### Source Code Modifications

When modifying the HA Controller source:

1. **Code Changes**: Edit files in `src/main/java/com/naevatec/ovrecorder/`
2. **Configuration**: Update `src/main/resources/application*.properties`
3. **Profile Management**: Use appropriate profile for development/testing
4. **Build**: Use Maven to build the application
5. **Deploy**: Use Docker Compose to deploy updated container

```bash
# After making changes
mvn clean package
docker compose build ov-recorder-ha-controller
docker compose up -d ov-recorder-ha-controller

# Test changes
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/health
```

## 🗃️ Image Building Details

### Custom Dockerfiles

The project uses two separate Dockerfiles:

#### HA Controller (`server/Dockerfile`)
- **Base**: OpenJDK 17 with multi-stage build
- **Build Stage**: Maven build with dependency caching
- **Runtime Stage**: Lightweight JRE with security hardening
- **Features**: Health checks, non-root user, proper logging
- **Profiles**: Support for environment-specific configurations

#### OpenVidu Recording (`recorder/Dockerfile`)
- **Base**: Ubuntu 24.04 or existing OpenVidu image
- **Components**: Chrome, FFmpeg, PulseAudio, Xvfb
- **Integration**: HA Controller connectivity scripts
- **Scripts**: Custom recording and utility scripts with HA integration
- **Dependencies**: curl, jq for API communication
- **Maintainer**: `"NaevaTec-OpenVidu eiglesia@openvidu.io"`

### Build Process

The build process automatically:
1. Builds HA Controller from source using Maven
2. Removes images with old maintainer labels
3. Builds new OpenVidu recording image with HA integration scripts
4. Verifies correct maintainer labels
5. Integrates all services with MinIO and Redis
6. Tests HA Controller API functionality
7. Validates Swagger documentation accessibility

### Image Versioning

Images are tagged using the `IMAGE_TAG` environment variable:
- **HA Controller**: Uses project version from `pom.xml`
- **OpenVidu Recording**: Uses `IMAGE_TAG` environment variable
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
- Swagger UI enabled in development/test profiles only

### Production Deployment

For production use:

1. **Change default credentials**:
   ```bash
   HA_AWS_ACCESS_KEY=your-secure-access-key
   HA_AWS_SECRET_KEY=your-secure-secret-key
   HA_CONTROLLER_USERNAME=your-secure-username
   HA_CONTROLLER_PASSWORD=your-very-secure-password
   ```

2. **Set production profile**:
   ```bash
   SPRING_PROFILES_ACTIVE=prod
   SWAGGER_ENABLED=false
   SWAGGER_UI_ENABLED=false
   ```

3. **Secure Redis**:
   - Enable Redis AUTH
   - Use Redis over TLS
   - Restrict network access

4. **HA Controller Security**:
   - Use HTTPS with SSL certificates
   - Implement JWT tokens instead of Basic Auth
   - Add rate limiting and request validation
   - Disable Swagger in production (automatic with prod profile)

5. **Use proper bucket policies**:
   - Remove public access
   - Implement least-privilege access

6. **Network security**:
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
   # Development mode with Swagger enabled
   SPRING_PROFILES_ACTIVE=dev mvn spring-boot:run
   # Test on http://localhost:8080
   # Swagger UI: http://localhost:8080/swagger-ui.html
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

# Test Swagger after changes (dev profile)
curl http://localhost:8080/swagger-ui.html

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

# Manual session management test with chunk tracking
curl -u recorder:rec0rd3r_2024! -X POST http://localhost:8080/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"sessionId":"test-session","clientId":"client-01","clientHost":"localhost"}'

# Test heartbeat with chunk progression
curl -u recorder:rec0rd3r_2024! -X PUT http://localhost:8080/api/sessions/test-session/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"lastChunk":"0001.mp4"}'

curl -u recorder:rec0rd3r_2024! -X PUT http://localhost:8080/api/sessions/test-session/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"lastChunk":"0002.mp4"}'

# Verify chunk tracking
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/test-session

# Clean up
curl -u recorder:rec0rd3r_2024! -X DELETE http://localhost:8080/api/sessions/test-session
```

### Profile-based Testing

```bash
# Test with development profile (Swagger enabled)
SPRING_PROFILES_ACTIVE=dev docker compose up -d ov-recorder-ha-controller
curl http://localhost:8080/swagger-ui.html  # Should return 200

# Test with production profile (Swagger disabled)
SPRING_PROFILES_ACTIVE=prod docker compose up -d ov-recorder-ha-controller
curl http://localhost:8080/swagger-ui.html  # Should return 404

# Test API functionality in both profiles
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/health  # Should work in both
```

## 🤝 Contributing

### Script Modifications

When modifying scripts:

1. **Test thoroughly** with `./validate-env.sh`
2. **Update documentation** in this README
3. **Maintain backward compatibility** where possible
4. **Follow existing naming conventions**
5. **Test with both development and production configurations**
6. **Verify 30-second container shutdown compliance**
7. **Test HA Controller integration functionality**

### HA Controller Development

When modifying HA Controller source:

1. **Follow SpringBoot best practices**
2. **Maintain API compatibility**
3. **Add comprehensive tests**
4. **Update API documentation and Swagger annotations**
5. **Test with real Redis instances**
6. **Verify profile-based configuration works correctly**
7. **Test both development and production profiles**
8. **Ensure Swagger documentation is accurate**

### Environment Variables

When adding new environment variables:

1. **Add to `.env` template**
2. **Update validation script**
3. **Document in this README**
4. **Update Docker Compose if needed**
5. **Add to HA Controller configuration if applicable**
6. **Add to recorder container scripts if needed**
7. **Test with all profiles (dev, test, prod)**

### API Endpoint Changes

When modifying API endpoints:

1. **Update Swagger annotations**
2. **Maintain backward compatibility**
3. **Update integration scripts in recorder container**
4. **Test with actual recording workflows**
5. **Update example scripts and documentation**
6. **Verify authentication requirements**

## 🎯 HA Failover Implementation

With the chunk tracking system in place, you can now implement intelligent failover logic:

### Example Failover Detection

```java
@Component
public class FailoverDetector {
    
    @Value("${app.chunk.time-size:10}")
    private int chunkTimeSize;
    
    @Scheduled(fixedDelay = 30000) // Check every 30 seconds
    public void detectFailedRecordings() {
        List<RecordingSession> sessions = sessionService.getAllActiveSessions();
        
        for (RecordingSession session : sessions) {
            long timeSinceHeartbeat = getSecondsSince(session.getLastHeartbeat());
            
            // If no heartbeat for 3 * CHUNK_TIME_SIZE + buffer (30s)
            long maxInactiveTime = (chunkTimeSize * 3) + 30;
            
            if (timeSinceHeartbeat > maxInactiveTime) {
                log.warn("Session {} appears failed - no heartbeat for {}s (limit: {}s)", 
                    session.getSessionId(), timeSinceHeartbeat, maxInactiveTime);
                
                // Trigger failover
                triggerRecordingFailover(session);
            }
        }
    }
    
    @Scheduled(fixedDelay = 45000) // Check every 45 seconds
    public void detectStuckRecordings() {
        List<RecordingSession> sessions = sessionService.getAllActiveSessions();
        
        for (RecordingSession session : sessions) {
            String currentChunk = session.getLastChunk();
            
            if (currentChunk != null) {
                long timeSinceHeartbeat = getSecondsSince(session.getLastHeartbeat());
                
                // If same chunk for more than 2 * CHUNK_TIME_SIZE
                long stuckThreshold = chunkTimeSize * 2;
                
                if (timeSinceHeartbeat > stuckThreshold && 
                    currentChunk.equals(getPreviousChunk(session))) {
                    
                    log.warn("Session {} appears stuck - same chunk '{}' for {}s", 
                        session.getSessionId(), currentChunk, timeSinceHeartbeat);
                    
                    // Trigger failover
                    triggerRecordingFailover(session);
                }
            }
        }
    }
    
    private void triggerRecordingFailover(RecordingSession session) {
        // Implement your failover logic here:
        // 1. Mark session as failed
        // 2. Start backup recorder
        // 3. Notify monitoring systems
        // 4. Handle chunk recovery if needed
        
        log.info("Triggering failover for session: {}", session.getSessionId());
        
        // Update session status
        sessionService.updateSessionStatus(session.getSessionId(), 
            RecordingSession.SessionStatus.FAILED);
        
        // Trigger backup recorder startup
        backupRecorderService.startFailoverRecording(session);
        
        // Send notifications
        notificationService.sendFailoverAlert(session);
    }
}
```

### Chunk-based Health Monitoring

```java
@RestController
@RequestMapping("/api/monitoring")
public class MonitoringController {
    
    @GetMapping("/health-detailed")
    public ResponseEntity<Map<String, Object>> getDetailedHealth() {
        List<RecordingSession> sessions = sessionService.getAllActiveSessions();
        
        Map<String, Object> health = new HashMap<>();
        health.put("totalSessions", sessions.size());
        health.put("timestamp", LocalDateTime.now());
        
        List<Map<String, Object>> sessionHealth = new ArrayList<>();
        
        for (RecordingSession session : sessions) {
            Map<String, Object> sessionInfo = new HashMap<>();
            sessionInfo.put("sessionId", session.getSessionId());
            sessionInfo.put("lastHeartbeat", session.getLastHeartbeat());
            sessionInfo.put("lastChunk", session.getLastChunk());
            sessionInfo.put("secondsSinceHeartbeat", getSecondsSince(session.getLastHeartbeat()));
            sessionInfo.put("status", session.getStatus());
            
            // Calculate expected vs actual chunks
            long recordingDuration = getSecondsSince(session.getCreatedAt());
            int expectedChunks = (int) (recordingDuration / chunkTimeSize);
            int actualChunk = extractChunkNumber(session.getLastChunk());
            
            sessionInfo.put("expectedChunks", expectedChunks);
            sessionInfo.put("actualChunks", actualChunk);
            sessionInfo.put("chunkLag", expectedChunks - actualChunk);
            
            sessionHealth.add(sessionInfo);
        }
        
        health.put("sessions", sessionHealth);
        return ResponseEntity.ok(health);
    }
}
```

## 📊 Performance Optimization

### Container Shutdown Optimization

The current implementation is optimized for the 30-second container shutdown requirement:

1. **Immediate Process Termination**: Use `KILL` signals instead of graceful `TERM`
2. **Background HA Operations**: All HA calls run in background
3. **Single API Call**: Use `DELETE` instead of multiple status updates
4. **Parallel Execution**: HA cleanup runs parallel with essential tasks
5. **Timeout Protection**: All API calls have short timeouts (5-10 seconds)

### Expected Timeline

```
Container Shutdown Timeline (30-second deadline):
T+0s    🛑 FFmpeg receives stop signal
T+1s    🧹 Background HA cleanup starts (non-blocking)
T+2s    🖼️ Thumbnail generation (priority)
T+5s    🔒 File permissions (priority)
T+8s    ☁️ S3 operations (if enabled)
T+15s   ✅ All essential tasks complete
T+30s   📦 Container exit deadline
```

### Performance Monitoring

Monitor HA Controller performance:

```bash
# Check API response times
curl -w "Time: %{time_total}s\n" -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/health

# Monitor Redis performance
docker compose exec redis redis-cli info stats

# Check container resource usage
docker stats ov-recorder-ha-controller

# Monitor session cleanup efficiency
curl -u recorder:rec0rd3r_2024! http://localhost:8080/api/sessions/cleanup
```

## 📚 References

- [OpenVidu Documentation](https://docs.openvidu.io/)
- [MinIO Documentation](https://docs.min.io/)
- [SpringBoot Documentation](https://spring.io/projects/spring-boot)
- [Redis Documentation](https://redis.io/documentation)
- [SpringDoc OpenAPI 3 Documentation](https://springdoc.org/)
- [Docker Compose Profiles](https://docs.docker.com/compose/profiles/)
- [NaevaTec OpenVidu Integration](https://github.com/naevatec/ov2-ha-recorder)

## 🏷️ Version History

### Current Version
- **HA Controller**: SpringBoot 3.2.12 with Java 21
- **OpenVidu Integration**: Custom NaevaTec recording image
- **Features**: 
  - Simplified session management (register, heartbeat, deregister)
  - Real-time chunk tracking
  - Profile-based Swagger documentation
  - 30-second container shutdown optimization
  - Comprehensive failover detection capabilities

### Key Improvements
- **Simplified API**: Removed unnecessary status updates and complex workflows
- **Chunk Tracking**: Real-time monitoring of recording progress
- **Fast Shutdown**: Optimized for container deadline compliance
- **Profile Management**: Environment-specific configurations
- **Documentation**: Interactive Swagger UI for development
- **Monitoring**: Enhanced session health tracking

---

**NaevaTec - OpenVidu2 HA Recorder Development Environment with HA Controller**  
For support: info@naevatec.com

**Quick Links:**
- API Documentation: http://localhost:8080/swagger-ui.html (dev/test)
- Health Check: http://localhost:8080/api/sessions/health
- MinIO Console: http://localhost:9001
- Project Repository: https://github.com/naevatec/ov2-ha-recorder
